var ctx = document.getElementById("paint").getContext("2d");

// A vertical sky.
var sky = ctx.createLinearGradient(0, 0, 0, 100);
sky.addColorStop(0, "#1e3a8a");
sky.addColorStop(1, "#93c5fd");
ctx.fillStyle = sky;
ctx.fillRect(0, 0, 300, 100);

// A radial sun, brightest at its centre.
var sun = ctx.createRadialGradient(240, 40, 4, 240, 40, 48);
sun.addColorStop(0, "#fffbeb");
sun.addColorStop(1, "#f59e0b");
ctx.fillStyle = sun;
ctx.fillRect(180, 0, 120, 100);

// A gradient stroke: red at the left, green at the right.
var stripe = ctx.createLinearGradient(0, 125, 300, 125);
stripe.addColorStop(0, "#dc2626");
stripe.addColorStop(1, "#16a34a");
ctx.strokeStyle = stripe;
ctx.lineWidth = 12;
ctx.beginPath();
ctx.moveTo(20, 125);
ctx.lineTo(280, 125);
ctx.stroke();
