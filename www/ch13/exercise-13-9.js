// Each box reports its id when hit. Correct hit testing means the id
// matches the box you visually clicked, even under stacked transforms.
function report(id) {
  return function () {
    document.querySelectorAll("#status")[0].innerHTML =
      "Hit: " + id;
  };
}

var ids = ["plain", "shifted", "inner", "under", "over"];
for (var i = 0; i < ids.length; i++) {
  document
    .querySelectorAll("#" + ids[i])[0]
    .addEventListener("click", report(ids[i]));
}
