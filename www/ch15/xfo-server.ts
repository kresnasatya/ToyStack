// Serves the Chapter 15 demos and stamps X-Frame-Options on the two pages that
// demonstrate it. Run from the repo root, then open the URL it prints:
//
//     bun run www/ch15/xfo-server.ts
//
const root = new URL(".", import.meta.url).pathname;

const frameOptions: Record<string, string> = {
  "xfo-deny.html": "DENY",
  "xfo-sameorigin.html": "SAMEORIGIN",
};

Bun.serve({
  port: 3000,
  async fetch(request) {
    const pathname = new URL(request.url).pathname;
    const name = pathname === "/" ? "index.html" : pathname.slice(1);
    const file = Bun.file(root + name);
    if (!(await file.exists())) {
      return new Response("Not found", { status: 404 });
    }
    const headers: Record<string, string> = {};
    const value = frameOptions[name];
    if (value) {
      headers["X-Frame-Options"] = value;
    }
    return new Response(file, { headers });
  },
});

console.log("Open http://localhost:3000/example15-xfo.html");
