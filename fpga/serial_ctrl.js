#!/usr/bin/env bun
import { execSync } from "node:child_process";
import fs from "node:fs";

const port = process.argv[2] || "/dev/ttyUSB1";
const commands = process.argv.slice(3);

if (commands.length === 0) {
  console.log("Usage: bun fpga/serial_ctrl.js <port=/dev/ttyUSB1> <cmd1> [cmd2 ...]");
  console.log("Commands:");
  console.log("  ?        query current 3-bit state, (q,r,s), angle, delta, role, orbit");
  console.log("  c/+/f    step +60 deg CCW along Gray Ring (dlt=1)");
  console.log("  a/-/b    step -60 deg CW along Gray Ring (dlt=1)");
  console.log("  0/z      jump to Centro 3'b000 (0,0,0)");
  console.log("  1..6     jump directly to Ring index 1..6");
  console.log("  s/x      jump to Sentinela 3'b100");
  console.log("  g<bbb>   set arbitrary 3-bit code (ex: g011, g100, g000)");
  console.log("  o        toggle ~1 Hz auto-orbit");
  console.log("  r        reset to 3'b001 and stop auto-orbit");
  process.exit(0);
}

if (!fs.existsSync(port)) {
  console.error(`Serial device not found: ${port}`);
  process.exit(1);
}

execSync(`stty -F ${port} 115200 raw -echo -echoe -echok -onlcr -icrnl`);

for (const cmd of commands) {
  const res = execSync(
    `python3 -c '
import os, select, sys
fd = os.open(sys.argv[1], os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
while select.select([fd], [], [], 0.01)[0]:
    if not os.read(fd, 1024): break
os.write(fd, sys.argv[2].encode())
out = b""
for _ in range(20):
    r, _, _ = select.select([fd], [], [], 0.05)
    if not r:
        if b"\\n" in out: break
        continue
    chunk = os.read(fd, 256)
    if not chunk: break
    out += chunk
    if b"\\n" in out: break
os.close(fd)
sys.stdout.write(out.decode(errors="replace").strip())
' "${port}" "${cmd}"`,
    { encoding: "utf8" }
  ).trim();
  console.log(`> ${cmd} -> ${res}`);
}
