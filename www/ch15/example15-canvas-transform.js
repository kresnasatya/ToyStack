var ctx = document.getElementById("turn").getContext("2d");

ctx.fillStyle = "#f0f4f8";
ctx.fillRect(0, 0, 300, 150);

ctx.fillStyle = "red";
for (var i = 0; i < 6; i++) {
  ctx.save();
  ctx.translate(50 + i * 40, 100);
  ctx.rotate((i / 12) * Math.PI);
  ctx.fillRect(-15, -15, 30, 30);
  ctx.restore();
}

// Scaling happens around the origin, so this square lands at 4x its coords.
ctx.fillStyle = "blue";
ctx.save();
ctx.scale(2, 2);
ctx.fillRect(15, 15, 20, 10);
ctx.restore();

// setTransform replaces everything, including the loop's leftovers.
ctx.setTransform(1, 0, 0, 1, 0, 0);
ctx.fillStyle = "green";
ctx.fillText("identity again", 180, 30);
