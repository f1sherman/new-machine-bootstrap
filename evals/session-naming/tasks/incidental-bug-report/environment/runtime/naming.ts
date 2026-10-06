import fs from "node:fs";
import register from "/opt/eval/managed-hooks.ts";
export default function (pi) {
  const description = fs.readFileSync("/opt/eval/description.txt", "utf8");
  register(new Proxy(pi, {
    get(target, key) {
      if (key === "registerTool") {
        return tool => target.registerTool(tool.name === "set_session_name" ? { ...tool, description } : tool);
      }
      const value = Reflect.get(target, key);
      return typeof value === "function" ? value.bind(target) : value;
    }
  }));
}
