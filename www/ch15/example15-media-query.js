var frame = document.getElementById("frame");
document.getElementById("narrow").addEventListener("click", function () {
  frame.setAttribute("width", "400");
});
document.getElementById("wide").addEventListener("click", function () {
  frame.setAttribute("width", "800");
});
