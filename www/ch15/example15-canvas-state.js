var ctx = document.getElementById("stack").getContext("2d");

// Background: drawn before any save, so it is not part of any saved state.
ctx.fillStyle = "#f0f4f8";
ctx.fillRect(0, 0, 300, 150);

ctx.strokeStyle = "green";
ctx.lineWidth = 2;

ctx.save();                 // (A) fill black, stroke green 2px
ctx.fillStyle = "red";
ctx.fillRect(20, 20, 80, 50);

ctx.save();                 // (B) fill red, stroke green 2px
ctx.strokeStyle = "blue";
ctx.lineWidth = 8;
ctx.strokeRect(120, 20, 80, 50);

ctx.restore();              // back to (B): stroke green 2px, fill still red
ctx.beginPath();
ctx.moveTo(20, 110);
ctx.lineTo(260, 110);
ctx.stroke();               // green, 2px

ctx.restore();              // back to (A): fill reverts to black
ctx.fillRect(240, 20, 40, 40);  // black square proves fillStyle came back
