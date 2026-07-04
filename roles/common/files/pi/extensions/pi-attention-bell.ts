const WRAPPED_MARKER = Symbol.for("nmb.piAttentionBell.wrappedUi");
const ATTENTION_METHODS = ["select", "confirm", "input", "editor", "custom"];

function requestAttention() {
  try {
    if (!process.stdout.isTTY) return;

    process.stdout.write("\x07");
  } catch {
    // Attention must never break Pi interaction.
  }
}

function wrapUiMethod(ui, methodName) {
  const original = ui[methodName];
  if (typeof original !== "function") return;

  ui[methodName] = function wrappedAttentionMethod(...args) {
    requestAttention();
    return original.apply(this, args);
  };
}

function wrapAttentionUi(ui) {
  try {
    if (!ui || typeof ui !== "object") return;

    if (ui[WRAPPED_MARKER]) return;

    for (const methodName of ATTENTION_METHODS) {
      wrapUiMethod(ui, methodName);
    }

    ui[WRAPPED_MARKER] = true;
  } catch {
    // Fail open: Pi should keep working even if its UI object changes.
  }
}

export default function piAttentionBell(pi) {
  pi.on("agent_end", async () => {
    requestAttention();
  });

  pi.on("session_start", async (_event, ctx) => {
    wrapAttentionUi(ctx?.ui);
  });
}
