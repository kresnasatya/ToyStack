var ctx = document.getElementById("board").getContext("2d");

ctx.fillStyle = "white";
ctx.fillRect(0, 0, 300, 150);

ctx.fillStyle = "red";
ctx.fillRect(20, 20, 60, 60);

ctx.strokeStyle = "blue";
ctx.lineWidth = 4;
ctx.strokeRect(100, 20, 120, 60);

ctx.beginPath();
ctx.moveTo(20, 130);
ctx.lineTo(120, 80);
ctx.lineTo(220, 130);
ctx.strokeStyle = "green";
ctx.stroke();

ctx.fillStyle = "orange";
ctx.beginPath();
ctx.moveTo(20, 130);
ctx.lineTo(120, 80);
ctx.lineTo(120, 130);
ctx.fill();

ctx.fillStyle = "black";
ctx.font = "16px serif";
ctx.fillText("Hello canvas", 180, 140);
