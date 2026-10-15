var parentWindow = window.parent;

if (parentWindow) {
  // window.origin is this frame's own origin, read at run time -- no port literal.
  // The parent is same-origin with us here, so this is a matching target origin.
  var sameOrigin = window.origin;

  // 1. Wildcard: allowed from any receiver origin.
  parentWindow.postMessage("wildcard * -> delivered", "*");

  // 2. The parent's real origin: must match exactly.
  parentWindow.postMessage("same origin -> delivered", sameOrigin);

  // 3. A foreign origin: dropped before the `message` event fires.
  parentWindow.postMessage("foreign origin -> dropped", "http://example.com");
}
