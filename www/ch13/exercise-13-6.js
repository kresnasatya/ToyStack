// Kick off after first frame, then toggle the transform forever.
// Mirrors exercise-13-3.js: transform animates via a CSS transition,
// driven by JS restyling (the engine's @keyframes path does not
// support transform, so we use transition + setTimeout).

var count = 0;
function frame() {
  if (count == 1) {
    go();
  } else {
    count++;
    requestAnimationFrame(frame);
  }
}
requestAnimationFrame(frame);

var over = false;
var mover = document.querySelectorAll("div")[1];
function go() {
  over = !over;
  if (over)
    // slide right so the blue box lands on top of the salmon box
    mover.style = "transform:translate(220px, 0px)";
  else
    mover.style = "transform:translate(0px, 0px)";
  setTimeout(go, 16 * 150);
}
