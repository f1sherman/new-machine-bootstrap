// The package remains installed, but its original factory loads only outside BB.
// Its settings entry uses extensions: [] to avoid a second registration.
export default async function nativeSessionBrowser(pi) {
  if (process.env.BB_THREAD_ID?.trim()) return;
  const { default: sessionBrowser } = await import(
    "../npm/node_modules/pi-session-manager/extensions/session-manager.ts"
  );
  await sessionBrowser(pi);
}
