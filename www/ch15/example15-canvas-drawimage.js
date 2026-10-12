var img = document.getElementById("photo");
var ctx = document.getElementById("paste").getContext("2d");

ctx.fillStyle = "#f0f4f8";
ctx.fillRect(0, 0, 300, 150);

// 3-arg: the whole image at its natural size, top-left at (10, 10).
ctx.drawImage(img, 10, 10);

// 5-arg: squashed into a 100x60 box.
ctx.drawImage(img, 150, 10, 100, 60);

// 9-arg: crop a 400x300 region out of the middle, then scale it and lean on the
// transform from part 1 while drawing.
ctx.save();
ctx.translate(30, 90);
ctx.scale(0.5, 0.5);
ctx.drawImage(img, 400, 300, 400, 300, 0, 0, 400, 300);
ctx.restore();
