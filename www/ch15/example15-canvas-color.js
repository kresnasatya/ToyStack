var ctx = document.getElementById("swatches").getContext("2d");

ctx.fillStyle = "#f0f4f8";
ctx.fillRect(0, 0, 320, 160);

// Hex with alpha (8-digit).
ctx.fillStyle = "#ff000080";
ctx.fillRect(20, 20, 80, 50);

// Functional rgb() with percent channels.
ctx.fillStyle = "rgb(0% 50% 100%)";
ctx.fillRect(120, 20, 80, 50);

// hsl() and hsla().
ctx.fillStyle = "hsl(120, 100%, 40%)";
ctx.fillRect(220, 20, 80, 50);
ctx.fillStyle = "hsla(240, 100%, 50%, 0.4)";
ctx.fillRect(20, 90, 130, 50);

// Stroke color from rgba().
ctx.strokeStyle = "rgba(255, 140, 0, 0.9)";
ctx.lineWidth = 6;
ctx.strokeRect(180, 90, 120, 50);

// invalid value must leave the previous stroke color alone.
ctx.strokeStyle = "definitely-not-a-color";
ctx.beginPath();
ctx.moveTo(40, 150);
ctx.lineTo(280, 150);
ctx.stroke();
