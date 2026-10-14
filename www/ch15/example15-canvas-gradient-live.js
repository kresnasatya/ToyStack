var ctx = document.getElementById("paint").getContext("2d");

// Assign the gradient BEFORE adding stops: the fill must still see them.
var stripe = ctx.createLinearGradient(0, 0, 300, 0);
ctx.fillStyle = stripe;
stripe.addColorStop(0, "#dc2626");
stripe.addColorStop(1, "#16a34a");
ctx.fillRect(0, 0, 300, 150);

// Out-of-range offset must throw, not silently clamp.
try {
  stripe.addColorStop(2, "red");
} catch (e) {
  console.log("offset error: " + e.name);
}
