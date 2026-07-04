var box = document.querySelectorAll("div")[0];
var faded = false;
function toggle() {
  faded = !faded;
  if (faded) {
    box.style.opacity = "0.2";
  } else {
    box.style.opacity = "0.9";
  }
  setTimeout(toggle, 2500);
}
setTimeout(toggle, 1000);
