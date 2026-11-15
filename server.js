import path from "node:path";

const ROOT = import.meta.dir;
const PORT = Number(process.env.PORT || 4174);

Bun.serve({
  port: PORT,
  fetch(req) {
    const pathname = new URL(req.url).pathname;
    const rel = pathname === "/" ? "index.html" : pathname.replace(/^\/+/, "");
    const resolved = path.resolve(ROOT, rel);
    if (!resolved.startsWith(ROOT)) {
      return new Response("Forbidden", { status: 403 });
    }
    return new Response(Bun.file(resolved));
  },
});

console.log(`Serving hex-gray-3d at http://localhost:${PORT}`);
