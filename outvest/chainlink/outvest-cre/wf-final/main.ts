import { CronCapability, Runner, handler, type Runtime } from '@chainlink/cre-sdk'
import { runViewsReport, type ViewsCfg } from '../common/views'

type Config = ViewsCfg & { schedule: string }

// Runs on a cron; the shared routine only sends FINAL once bindDeadline + scheduleLength has passed.
const onCron = (runtime: Runtime<Config>): string => runViewsReport(runtime, 'FINAL')

const initWorkflow = (config: Config) => [
  handler(new CronCapability().trigger({ schedule: config.schedule }), onCron),
]

export async function main() {
  const runner = await Runner.newRunner<Config>()
  await runner.run(initWorkflow)
}
main()
