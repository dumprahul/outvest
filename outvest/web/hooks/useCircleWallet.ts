"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import type { W3SSdk } from "@circle-fin/w3s-pw-web-sdk";
import type { SocialLoginProvider } from "@circle-fin/w3s-pw-web-sdk/dist/src/types";
import {
  circleApi,
  deviceStore,
  pendingLoginStore,
  sessionStore,
  usdcBalance,
  type Session,
  type TokenBalance,
  type Wallet,
} from "@/lib/circle-client";

export type Step = "loading" | "email" | "otp" | "wallet" | "ready";

const APP_ID = process.env.NEXT_PUBLIC_CIRCLE_APP_ID ?? "";
const GOOGLE_CLIENT_ID = process.env.NEXT_PUBLIC_GOOGLE_CLIENT_ID ?? "";

const googleConfig = () => ({ clientId: GOOGLE_CLIENT_ID, redirectUri: window.location.origin, selectAccountPrompt: true });
const msg = (e: unknown) => (e instanceof Error ? e.message : String((e as { message?: string })?.message ?? e));

/**
 * Drives Circle user-controlled onboarding:
 * email -> OTP (Circle hosted UI) -> PIN + wallet creation challenge -> wallet ready.
 * Keys and PIN never touch our code; the SDK handles them in Circle's iframe.
 */
export function useCircleWallet() {
  const sdkRef = useRef<W3SSdk | null>(null);
  const emailRef = useRef("");
  const [step, setStep] = useState<Step>("loading");
  const [session, setSession] = useState<Session | null>(null);
  const [wallet, setWallet] = useState<Wallet | null>(null);
  const [usdc, setUsdc] = useState("0");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const loadWallet = useCallback(async (s: Session): Promise<boolean> => {
    const { wallets } = await circleApi<{ wallets: Wallet[] }>("listWallets", { userToken: s.userToken });
    const w = wallets?.[0];
    if (!w) return false;
    setWallet(w);
    try {
      const { tokenBalances } = await circleApi<{ tokenBalances: TokenBalance[] }>("getBalances", {
        userToken: s.userToken,
        walletId: w.id,
      });
      setUsdc(usdcBalance(tokenBalances ?? []));
    } catch {
      // Balance is cosmetic; the wallet itself is ready.
    }
    return true;
  }, []);

  /** After login: create the wallet (PIN setup) if the user has none, otherwise go straight in. */
  const afterLogin = useCallback(
    async (s: Session) => {
      setSession(s);
      sessionStore.save(s);
      const init = await circleApi<{ challengeId?: string; alreadyInitialized?: boolean }>("initializeUser", {
        userToken: s.userToken,
      });
      if (init.alreadyInitialized || !init.challengeId) {
        if (await loadWallet(s)) return setStep("ready");
        throw new Error("Account exists but no wallet was found. Please contact support.");
      }
      setStep("wallet");
      const sdk = sdkRef.current!;
      sdk.setAuthentication({ userToken: s.userToken, encryptionKey: s.encryptionKey });
      sdk.execute(init.challengeId, async (err) => {
        if (err) {
          setError(msg(err));
          setBusy(false);
          return;
        }
        try {
          // Circle indexes the new wallet asynchronously.
          for (let i = 0; i < 5; i++) {
            await new Promise((r) => setTimeout(r, 2000));
            if (await loadWallet(s)) return setStep("ready");
          }
          throw new Error("Wallet created but not visible yet. Refresh in a moment.");
        } catch (e) {
          setError(msg(e));
        } finally {
          setBusy(false);
        }
      });
    },
    [loadWallet],
  );

  // SDK is browser-only; import lazily, then restore any live session.
  useEffect(() => {
    let cancelled = false;
    (async () => {
      try {
        if (!APP_ID) throw new Error("NEXT_PUBLIC_CIRCLE_APP_ID is not set");
        const { W3SSdk } = await import("@circle-fin/w3s-pw-web-sdk");
        // Returning from Google's redirect: rebuild the SDK with the saved device tokens so it can finish login.
        const pending = pendingLoginStore.load();
        const sdk = new W3SSdk(
          {
            appSettings: { appId: APP_ID },
            ...(pending && GOOGLE_CLIENT_ID ? { loginConfigs: { ...pending, google: googleConfig() } } : {}),
          },
          (err, result) => {
          pendingLoginStore.clear();
          if (err || !result) {
            setError(msg(err ?? "Login failed"));
            setBusy(false);
            setStep("email");
            return;
          }
          afterLogin({
            userToken: result.userToken,
            encryptionKey: result.encryptionKey,
            email: emailRef.current,
          }).catch((e) => setError(msg(e))).finally(() => setBusy(false));
          },
        );
        if (cancelled) return;
        sdkRef.current = sdk;

        const saved = sessionStore.load();
        if (saved) {
          setSession(saved);
          try {
            if (await loadWallet(saved)) return setStep("ready");
          } catch {
            sessionStore.clear(); // token expired
          }
        }
        if (pending) {
          // Callback fires on return from Google; if it never does (reload/cancel), fall back to the form.
          setTimeout(() => {
            pendingLoginStore.clear();
            setStep((s) => (s === "loading" ? "email" : s));
          }, 15000);
          return;
        }
        setStep("email");
      } catch (e) {
        setError(msg(e));
        setStep("email");
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [afterLogin, loadWallet]);

  const sendOtp = useCallback(async (email: string) => {
    const sdk = sdkRef.current;
    if (!sdk) return;
    setBusy(true);
    setError(null);
    try {
      let deviceId = deviceStore.load();
      if (!deviceId) {
        deviceId = await sdk.getDeviceId();
        deviceStore.save(deviceId);
      }
      emailRef.current = email;
      const { deviceToken, deviceEncryptionKey, otpToken } = await circleApi<{
        deviceToken: string;
        deviceEncryptionKey: string;
        otpToken: string;
      }>("requestEmailOtp", { email, deviceId });
      sdk.updateConfigs({
        appSettings: { appId: APP_ID },
        loginConfigs: { deviceToken, deviceEncryptionKey, otpToken },
      });
      setStep("otp");
    } catch (e) {
      setError(msg(e));
    } finally {
      setBusy(false);
    }
  }, []);

  /** Redirects to Google; the flow resumes in the constructor callback when the user returns. */
  const signInWithGoogle = useCallback(async () => {
    const sdk = sdkRef.current;
    if (!sdk) return;
    setBusy(true);
    setError(null);
    try {
      if (!GOOGLE_CLIENT_ID) throw new Error("NEXT_PUBLIC_GOOGLE_CLIENT_ID is not set");
      let deviceId = deviceStore.load();
      if (!deviceId) {
        deviceId = await sdk.getDeviceId();
        deviceStore.save(deviceId);
      }
      const tokens = await circleApi<{ deviceToken: string; deviceEncryptionKey: string }>("requestSocialToken", {
        deviceId,
      });
      pendingLoginStore.save(tokens);
      sdk.updateConfigs({ appSettings: { appId: APP_ID }, loginConfigs: { ...tokens, google: googleConfig() } });
      await sdk.performLogin("Google" as SocialLoginProvider);
    } catch (e) {
      setError(msg(e));
      setBusy(false);
    }
  }, []);

  /** Opens Circle's hosted OTP screen; onLoginComplete continues the flow. */
  const verifyOtp = useCallback(() => {
    setBusy(true);
    setError(null);
    sdkRef.current?.verifyOtp();
  }, []);

  const refreshBalance = useCallback(async () => {
    if (session) await loadWallet(session).catch(() => {});
  }, [session, loadWallet]);

  /**
   * Asks Circle for a contract-execution challenge, then has the user approve it with their PIN.
   * Resolves once the user approved; the transaction itself confirms onchain a few seconds later.
   */
  const sendTx = useCallback(
    async (contractAddress: string, abiFunctionSignature: string, abiParameters: unknown[], amount?: string) => {
      const sdk = sdkRef.current;
      if (!sdk || !session || !wallet) throw new Error("Wallet is not ready");
      const { challengeId } = await circleApi<{ challengeId: string }>("executeContract", {
        userToken: session.userToken,
        walletId: wallet.id,
        contractAddress,
        abiFunctionSignature,
        abiParameters,
        ...(amount ? { amount } : {}),
      });
      sdk.setAuthentication({ userToken: session.userToken, encryptionKey: session.encryptionKey });
      await new Promise<void>((resolve, reject) => {
        sdk.execute(challengeId, (err) => (err ? reject(new Error(msg(err))) : resolve()));
      });
    },
    [session, wallet],
  );

  const signOut = useCallback(() => {
    sessionStore.clear();
    setSession(null);
    setWallet(null);
    setUsdc("0");
    setError(null);
    setStep("email");
  }, []);

  return { step, session, wallet, usdc, busy, error, sendOtp, verifyOtp, signInWithGoogle, refreshBalance, sendTx, signOut, setStep };
}
