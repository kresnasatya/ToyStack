var ctx = document.getElementById("board").getContext("2d");
var x = 0;

function frame() {
  ctx.clearRect(0, 0, 300, 150);
  ctx.fillStyle = "white";
  ctx.fillRect(0, 0, 300, 150);
  ctx.fillStyle = "red";
  ctx.fillRect(x, 60, 40, 40);
  x = (x + 4) % 300;
  requestAnimationFrame(frame);
}

requestAnimationFrame(frame);
