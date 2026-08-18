/**
 * dsh-omi-voice - minimal Node entry
 *
 * This plugin is pure client UI (read-aloud remote control for the local Omi
 * engine). The Node half is a no-op placeholder so the bundle mounts
 * cleanly; the client bundle loads via package.json exports["./client"] +
 * dsh.client.platform.
 */
const name = 'dsh-omi-voice'

export function apply(ctx) {
  // Pure client plugin: no Node-side logic needed.
}

export { name }
