// Drag to reorder behavior for ranking questions
// Use Pointer Events so mouse and touch run through one code path.
// (The native HTML 5 drag and drop API is not usable here: it does not fire on touch devices.)
// Handlers are registered ONCE on the document and work for every current and future ranking question,
// including reactive questions that re-render -- the same delegated approach used in interaction.js.

(function () {
  var dragging = null; // the <li> currently being dragged
  var draggingList = null; //its parent <ul>
  var interacted = {}; // question ids the respondent has actually dragged

  function itemsOf(list) {
    return Array.prototype.slice.call(
      list.querySelectorAll(".sd-ranking-item"),
    );
  }

  // Report the current top-to-bottom order to Shiny, pipe-joined to match
  // format_question_value()'s convention for multi-value answers(R/utils.R).
  function reportOrder(list) {
    var values = itemsOf(list).map(function (item) {
      return item.getAttribute("data-value");
    });
    Shiny.setInputValue(list.id, values.join("|"));
  }

  // Reorder the DOM to match a list of values. Values not present are
  // ignored; items not named in `order` keep their relative position after
  // the ones that are.

  function applyOrder(list, order) {
    var values = [].concat(order || []);
    var byValue = {};
    itemsOf(list).forEach(function (item) {
      byValue[item.getAttribute("data-value")] = item;
    });
    values.forEach(function (value) {
      if (byValue[value]) list.appendChild(byValue[value]);
    });
  }

  // The item the dragged element should be inserted before: the closest one
  // whose vertical midpoint sits below the pointer, null = past the last
  // item, so append.
  function itemAfter(list, y) {
    return itemsOf(list).reduce(
      function (closest, item) {
        if (item === dragging) return closest;
        var box = item.getBoundingClientRect();
        var offset = y - box.top - box.height / 2;
        if (offset < 0 && offset > closest.offset) {
          return { offset: offset, item: item };
        }
        return closest;
      },
      { offset: Number.NEGATIVE_INFINITY, item: null },
    ).item;
  }

  function markInteracted(id) {
    if (interacted[id]) return;
    interacted[id] = true;
    Shiny.setInputValue(id + "_interacted", true, { priority: "event" });
  }

  document.addEventListener("pointerdown", function (e) {
    var item = e.target.closest(".sd-ranking-item");
    if (!item) return;
    var list = item.closest(".sd-ranking-list");
    if (!list) return;

    // On touch, only the handle starts a drag. The item body keeps its
    // default touch-action, so swiping over a long list still scrolls the
    // page on mobile. A mouse can grab anywhere on the row.
    if (e.pointerType !== "mouse" && !e.target.closest(".sd-ranking-handle")) {
      return;
    }

    dragging = item;
    draggingList = list;
    item.classList.add("sd-ranking-dragging");

    // Capture on the LIST, not the item: reordering re-inserts the dragged
    // <li> into the DOM< which drops a capture held by the item itself.
    // ( and touch implicitly captures to the pointerdown target).
    list.setPointerCapture(e.pointerId);
  });

  document.addEventListener(
    "pointermove",
    function (e) {
      if (!dragging) return;
      e.preventDefault();
      var next = itemAfter(draggingList, e.clientY);
      if (next) {
        draggingList.insertBefore(dragging, next);
      } else {
        draggingList.appendChild(dragging);
      }
    },
    { passive: false },
  );

  function endDrag() {
    if (!dragging) return;
    var list = draggingList;
    dragging.classList.remove("sd-ranking-dragging");
    dragging = null;
    draggingList = null;
    reportOrder(list);
    markInteracted(list.id);
  }

  document.addEventListener("pointerup", endDrag);
  document.addEventListener("pointercancel", endDrag);

  // Restoration (Previous button, resumed session). Must NOT mark the
  // question as interacted -- restoring a saved answer is not a new
  // interaction, and treating it as one would advance the progress bar on
  // page load.
  Shiny.addCustomMessageHandler("restoreRankingOrder", function (message) {
    var list = document.getElementById(message.id);
    if (list) applyOrder(list, message.order);
  });

  // Test hook: headless browsers cannot reliably synthesize a drag gesture,
  // so the browser tests drive ordering through this instead.
  window.sdSetRankingOrder = function (id, order) {
    var list = document.getElementById(id);
    if (!list) return;
    applyOrder(list, order);
    reportOrder(list);
    markInteracted(id);
  };
})();
