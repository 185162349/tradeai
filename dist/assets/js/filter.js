/*
 * Adds a live filter box above every long tool list.
 * The box is injected by script so no template has to change and
 * the page still works when JavaScript is off.
 */
(function () {
  var lists = document.querySelectorAll('ul.tool-list');
  if (!lists.length) return;

  Array.prototype.forEach.call(lists, function (list) {
    var items = Array.prototype.slice.call(list.querySelectorAll('li'));
    if (items.length < 6) return; // short lists do not need filtering

    var bar = document.createElement('div');
    bar.className = 'filter-bar';

    var input = document.createElement('input');
    input.type = 'search';
    input.autocomplete = 'off';
    input.placeholder = 'Filter ' + items.length + ' tools by name, job or pricing…';
    input.setAttribute('aria-label', 'Filter tools');

    var count = document.createElement('span');
    count.className = 'filter-count';

    bar.appendChild(input);
    bar.appendChild(count);
    list.parentNode.insertBefore(bar, list);

    var empty = document.createElement('p');
    empty.className = 'filter-empty';
    empty.textContent = 'No tools match that search.';
    empty.hidden = true;
    list.parentNode.insertBefore(empty, list.nextSibling);

    input.addEventListener('input', function () {
      var q = input.value.trim().toLowerCase();
      var shown = 0;
      items.forEach(function (li) {
        var hit = !q || li.textContent.toLowerCase().indexOf(q) !== -1;
        li.hidden = !hit;
        if (hit) shown++;
      });
      count.textContent = q ? shown + ' of ' + items.length : '';
      empty.hidden = shown !== 0;
    });
  });
})();
