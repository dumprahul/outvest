"use client";

import { useEffect } from "react";

/**
 * Google redirects back to the site origin ("/") with the result in the URL fragment.
 * The Circle SDK that completes login lives on /get-started, so forward there, keeping the fragment.
 */
export function OAuthReturn() {
  useEffect(() => {
    const { hash } = window.location;
    if (/id_token=|access_token=/.test(hash)) {
      window.location.replace(`/get-started${hash}`);
    }
  }, []);
  return null;
}
