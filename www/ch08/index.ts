import get from "./get.html";
import post from "./post.html";

const server = Bun.serve({
  routes: {
    "/": new Response("OK"),
    "/get": get,
    "/post": post,
  },
});

console.log(`Server running at ${server.url}`);
