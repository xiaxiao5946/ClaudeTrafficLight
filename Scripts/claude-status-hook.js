#!/usr/bin/env node

const fs = require('fs')
const os = require('os')
const path = require('path')
const { spawn } = require('child_process')

const states = {
  SessionStart: 'idle',
  UserPromptSubmit: 'working',
  PreToolUse: 'working',
  PostToolUse: 'working',
  PostToolUseFailure: 'error',
  PermissionRequest: 'blocked',
  PermissionDenied: 'blocked',
  Stop: 'idle',
  StopFailure: 'error',
}

const hookEvents = [...Object.keys(states), 'SessionEnd']

function statusFor(event, input) {
  if (event === 'PostToolUseFailure') {
    if (input.is_interrupt === true) return 'idle'
    if (isPermissionWait(input)) return 'blocked'
    return null
  }
  return states[event]
}

function isPermissionWait(input) {
  const text = `${input.tool_use_result || ''}\n${input.error || ''}`.toLowerCase()
  return [
    "user rejected tool use",
    "user doesn't want to proceed",
    "permission for this action was denied",
    "requires explicit user authorization",
  ].some(marker => text.includes(marker))
}
function install() {
  const claudeDir = process.env.CLAUDE_CONFIG_DIR || path.join(os.homedir(), '.claude')
  const targetDir = path.join(claudeDir, 'trafficlight')
  const target = path.join(targetDir, 'claude-status-hook.js')
  const settingsPath = path.join(claudeDir, 'settings.json')

  fs.mkdirSync(targetDir, { recursive: true })
  if (path.resolve(__filename) !== target) fs.copyFileSync(__filename, target)
  fs.chmodSync(target, 0o755)

  const settings = fs.existsSync(settingsPath)
    ? JSON.parse(fs.readFileSync(settingsPath, 'utf8'))
    : {}
  settings.hooks ||= {}
  const command = `/usr/bin/env node ${JSON.stringify(target)}`

  for (const event of hookEvents) {
    const entries = settings.hooks[event] ||= []
    const exists = entries.some(entry =>
      entry.hooks?.some(hook => hook.command === command),
    )
    if (!exists) {
      entries.push({ matcher: '', hooks: [{ type: 'command', command }] })
    }
  }

  const temp = `${settingsPath}.${process.pid}.tmp`
  fs.writeFileSync(temp, `${JSON.stringify(settings, null, 2)}\n`)
  fs.renameSync(temp, settingsPath)
  return settingsPath
}

function assert(condition, message) {
  if (!condition) throw new Error(message)
}

if (process.argv[2] === '--install') {
  console.log(`Claude Traffic Light hooks installed in ${install()}`)
  process.exit(0)
}

if (process.argv[2] === '--self-test') {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'claude-traffic-light-'))
  process.env.CLAUDE_CONFIG_DIR = dir
  fs.writeFileSync(path.join(dir, 'settings.json'), JSON.stringify({
    hooks: { SessionStart: [{ hooks: [{ type: 'command', command: 'echo existing' }] }] },
  }))
  install()
  const settings = JSON.parse(fs.readFileSync(path.join(dir, 'settings.json'), 'utf8'))
  const installed = event => settings.hooks[event]?.some(entry =>
    entry.hooks?.some(hook => hook.command.includes('claude-status-hook.js')),
  )
  assert(states.UserPromptSubmit === 'working', 'normal work must stay green')
  assert(statusFor('PostToolUseFailure', {}) === null, 'generic tool failure must wait for JSONL')
  assert(statusFor('PostToolUseFailure', { is_interrupt: true }) === 'idle', 'user interrupt must not be red')
  assert(statusFor('PostToolUseFailure', { error: 'Permission for this action was denied' }) === 'blocked', 'permission wait stays yellow')
  assert(states.PermissionRequest === 'blocked', 'permission request must be yellow')
  assert(hookEvents.every(installed), 'all hooks must be installed')
  assert(settings.hooks.SessionStart[0].hooks[0].command === 'echo existing', 'existing hooks must be preserved')
  fs.rmSync(dir, { recursive: true, force: true })
  console.log('claude-status-hook self-test passed')
  process.exit(0)
}

try {
  const input = JSON.parse(fs.readFileSync(0, 'utf8') || '{}')
  const event = input.hook_event_name
  const sessionId = input.session_id
  if (event === 'SessionStart') {
    spawn('/usr/bin/open', ['-b', 'com.claude.trafficlight'], {
      detached: true,
      stdio: 'ignore',
    }).unref()
  }
  if (typeof sessionId !== 'string' || !/^[A-Za-z0-9._-]+$/.test(sessionId)) process.exit(0)

  const dir = process.env.CTL_HOOK_DIR || path.join(os.homedir(), '.claude', 'trafficlight', 'hooks')
  const file = path.join(dir, `${sessionId}.json`)
  if (event === 'SessionEnd') {
    fs.rmSync(file, { force: true })
    process.exit(0)
  }

  const status = statusFor(event, input)
  if (!status) process.exit(0)
  fs.mkdirSync(dir, { recursive: true })
  const temp = `${file}.${process.pid}.tmp`
  fs.writeFileSync(temp, JSON.stringify({ status, event, updated_at: Date.now() }))
  fs.renameSync(temp, file)
} catch {
  // Hooks must never interrupt Claude.
}
