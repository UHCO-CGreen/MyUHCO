<cfsetting showdebugoutput="false">
<cfscript>
if (!structKeyExists(session, "user")) {
  location("/login.cfm", false);
}

portalUser = session.user;
gradYearWindow = application.dateHelper.getGradYearWindow();
studentGradYears = [];
alumniGradYears = [];
studentYearStart = gradYearWindow.startYear;
studentYearEnd = gradYearWindow.endYear;
alumniStartYear = 1955;
alumniEndYear = gradYearWindow.startYear - 1;

for (y = gradYearWindow.startYear; y LTE gradYearWindow.endYear; y = y + 1) {
  arrayAppend(studentGradYears, y);
}

if (alumniEndYear LT alumniStartYear) {
  alumniEndYear = alumniStartYear;
}

for (y = alumniEndYear; y GTE alumniStartYear; y = y - 1) {
  arrayAppend(alumniGradYears, y);
}
</cfscript>
<cfoutput>
<div class="container-fluid">
  <div class="row g-4 mb-3">
    <div class="col-12">
      <section class="card border-0 shadow-sm portal-card">
        <div class="card-body p-4">
          <h1 class="h3 mb-2">College Directory</h1>
          <p class="mb-0">Use the filters to find faculty, staff, students, and alumni.</p>
        </div>
      </section>
    </div>
  </div>

  <div class="row g-4">
    <div class="col-12">
      <section class="card border-0 shadow-sm portal-card">
        <div class="card-body p-4">
          <div class="btn-group mb-3" role="group" aria-label="Directory groups">
            <button type="button" class="btn btn-outline-primary btn-sm directory-group-btn" data-group="faculty">Faculty</button>
            <button type="button" class="btn btn-outline-primary btn-sm directory-group-btn" data-group="staff">Staff</button>
            <button type="button" class="btn btn-outline-primary btn-sm directory-group-btn" data-group="students">Students</button>
            <button type="button" class="btn btn-outline-primary btn-sm directory-group-btn" data-group="alumni">Alumni</button>
          </div>

          <div id="dirGradFilterWrap" class="mb-2" style="display:none;">
            <label class="small mb-1" for="dirGradFilter">Class of</label>
            <select id="dirGradFilter" class="form-select form-select-sm" aria-label="Select class year">
              <option value="">Select class year to load...</option>
            </select>
          </div>

          <div id="directoryStatus" class="alert alert-secondary py-2" role="status">Click a group to load.</div>
          <div id="directoryTableWrap" style="display:none;">
            <div class="mb-2">
              <input type="search" id="dirSearch" class="form-control form-control-sm" placeholder="Search by last name..." autocomplete="off">
            </div>
            <div class="d-flex justify-content-between align-items-center mb-2">
              <div class="small text-muted" id="dirPageInfo"></div>
              <div class="d-flex align-items-center gap-2">
                <div class="btn-group btn-group-sm" role="group" aria-label="View mode">
                  <button type="button" id="dirViewTable" class="btn btn-outline-secondary active" title="Table view" aria-label="Table view"><i class="fas fa-list-alt"></i></button>
                  <button type="button" id="dirViewCards" class="btn btn-outline-secondary" title="Card view" aria-label="Card view"><i class="fas fa-th"></i></button>
                </div>
                <label class="small mb-0" for="dirPageSize">Per page:</label>
                <select id="dirPageSize" class="form-select form-select-sm" style="width:auto;">
                  <option value="10">10</option>
                  <option value="25" selected>25</option>
                  <option value="50">50</option>
                  <option value="200">All</option>
                </select>
              </div>
            </div>
            <div class="table-responsive">
              <table id="directoryTable" class="table table-sm table-hover align-middle mb-2">
                <thead id="directoryThead"></thead>
                <tbody id="directoryTbody"></tbody>
              </table>
            </div>
            <div id="dirCardGrid" class="row g-3" style="display:none;"></div>
            <div id="dirPagination" class="d-flex justify-content-center mt-1"></div>
          </div>

          <div class="modal fade" id="dirProfileModal" tabindex="-1" aria-labelledby="dirProfileModalLabel" aria-hidden="true">
            <div class="modal-dialog modal-dialog-centered">
              <div class="modal-content">
                <div class="modal-header">
                  <h5 class="modal-title" id="dirProfileModalLabel">Profile</h5>
                  <button type="button" id="dirProfileModalClose" class="btn-close" data-bs-dismiss="modal" aria-label="Close"></button>
                </div>
                <div class="modal-body" id="dirProfileModalBody"></div>
              </div>
            </div>
          </div>
        </div>
      </section>
    </div>
  </div>
</div>

<script>
  (function () {
    function initDirectoryModule() {
      if (!window.bootstrap) {
        console.error('Directory module could not initialize because Bootstrap is not available.');
        return;
      }

    var STUDENT_YEAR_OPTIONS = #serializeJSON(studentGradYears)#;
    var ALUMNI_YEAR_OPTIONS = #serializeJSON(alumniGradYears)#;
    var STUDENT_YEAR_START = #studentYearStart#;
    var STUDENT_YEAR_END = #studentYearEnd#;
    var ALUMNI_YEAR_START = #alumniStartYear#;
    var ALUMNI_YEAR_END = #alumniEndYear#;

    var statusEl = document.getElementById('directoryStatus');
    var wrapEl = document.getElementById('directoryTableWrap');
    var theadEl = document.getElementById('directoryThead');
    var tbodyEl = document.getElementById('directoryTbody');
    var pageInfoEl = document.getElementById('dirPageInfo');
    var pagCtrlEl = document.getElementById('dirPagination');
    var pagSizeEl = document.getElementById('dirPageSize');
    var searchEl = document.getElementById('dirSearch');
    var gradFilterWrapEl = document.getElementById('dirGradFilterWrap');
    var gradFilterEl = document.getElementById('dirGradFilter');
    var viewTableBtn = document.getElementById('dirViewTable');
    var viewCardsBtn = document.getElementById('dirViewCards');
    var cardGridEl = document.getElementById('dirCardGrid');
    var tableEl = document.getElementById('directoryTable');
    var profileModalEl = document.getElementById('dirProfileModal');
    var profileModal = new bootstrap.Modal(profileModalEl);
    var profileModalCloseBtn = document.getElementById('dirProfileModalClose');
    var profileTitle = document.getElementById('dirProfileModalLabel');
    var profileBody = document.getElementById('dirProfileModalBody');

    var STUDENT_GROUPS = ['students', 'alumni'];

    var state = {
      group: null,
      allData: [],
      search: '',
      gradYear: '',
      sort: { col: 'lastname', dir: 'asc' },
      page: 1,
      pageSize: 25,
      viewMode: 'table'
    };

    function setStatus(kind, msg) {
      statusEl.className = 'alert py-2' +
        (kind === 'error' ? ' alert-danger' : kind === 'success' ? ' alert-success' : ' alert-secondary');
      statusEl.textContent = msg;
    }

    function normPerson(raw) {
      var person = {};
      Object.keys(raw).forEach(function (key) { person[key.toLowerCase()] = raw[key]; });
      return person;
    }

    function getLastName(name) {
      var parts = (name || '').trim().split(/\s+/);
      return (parts.length > 1 ? parts[parts.length - 1] : parts[0] || '').toLowerCase();
    }

    function getName(person) {
      return person.fullname || person.displayname || person.name || person.username || '';
    }

    function getNameWithDegrees(person) {
      var name = getName(person);
      var degrees = person.combineddegrees || person.degrees || person.degree || '';
      return degrees ? name + ', ' + degrees : name;
    }

    function isStudentGroup(group) {
      return STUDENT_GROUPS.indexOf(group) >= 0;
    }

    function buildYearRange(startYear, endYear, descending) {
      var years = [];
      var year = startYear;

      if (descending) {
        for (year = endYear; year >= startYear; year -= 1) {
          years.push(year);
        }
        return years;
      }

      for (year = startYear; year <= endYear; year += 1) {
        years.push(year);
      }
      return years;
    }

    function normalizeYearOptions(rawOptions, group) {
      if (Array.isArray(rawOptions) && rawOptions.length) {
        return rawOptions;
      }

      if (group === 'students') {
        return buildYearRange(STUDENT_YEAR_START, STUDENT_YEAR_END, false);
      }

      if (group === 'alumni') {
        return buildYearRange(ALUMNI_YEAR_START, ALUMNI_YEAR_END, true);
      }

      return [];
    }

    function buildGradYearOptions(group) {
      var years = [];
      gradFilterEl.innerHTML = '<option value="">Select class year to load...</option>';

      if (group === 'students') {
        years = normalizeYearOptions(STUDENT_YEAR_OPTIONS, group);
      } else if (group === 'alumni') {
        years = normalizeYearOptions(ALUMNI_YEAR_OPTIONS, group);
      }

      years.forEach(function (year) {
        var option = document.createElement('option');
        option.value = String(year);
        option.textContent = String(year);
        gradFilterEl.appendChild(option);
      });
    }

    function getFacultyType(person) {
      var raw = (person.facultytype || person.faculty_type || person.facultyrole || '').toLowerCase();
      var flags = (person.flags || '').toLowerCase();
      var combined = raw + ' ' + flags;
      if (combined.indexOf('emerit') >= 0) return 'Professor Emeritus';
      if (combined.indexOf('adjunct') >= 0) return 'Adjunct Faculty';
      if (combined.indexOf('fulltime') >= 0 || combined.indexOf('full-time') >= 0) return 'Faculty';
      return raw ? (raw.charAt(0).toUpperCase() + raw.slice(1)) : 'Faculty';
    }

    function colDefs(group) {
      if (STUDENT_GROUPS.indexOf(group) >= 0) {
        return [
          { key: 'photo', label: '', sortKey: null },
          { key: 'fullname', label: 'Name', sortKey: 'lastname' },
          { key: 'program', label: 'Program', sortKey: 'program' },
          { key: 'gradyear', label: 'Class of', sortKey: 'gradyear' }
        ];
      }
      if (group === 'faculty') {
        return [
          { key: 'photo', label: '', sortKey: null },
          { key: 'fullname', label: 'Name', sortKey: 'lastname' },
          { key: 'facultytype', label: 'Type', sortKey: 'facultytype' },
          { key: 'title1', label: 'Title', sortKey: 'title1' },
          { key: 'email', label: 'Email', sortKey: 'email' },
          { key: 'phone', label: 'Phone', sortKey: 'phone' }
        ];
      }
      return [
        { key: 'photo', label: '', sortKey: null },
        { key: 'fullname', label: 'Name', sortKey: 'lastname' },
        { key: 'title1', label: 'Title', sortKey: 'title1' },
        { key: 'email', label: 'Email', sortKey: 'email' },
        { key: 'phone', label: 'Phone', sortKey: 'phone' }
      ];
    }

    function sortData(data) {
      var col = state.sort.col;
      var dir = state.sort.dir;
      return data.slice().sort(function (left, right) {
        var leftValue = '';
        var rightValue = '';
        if (col === 'lastname') {
          leftValue = getLastName(getName(left));
          rightValue = getLastName(getName(right));
        } else if (col === 'email') {
          leftValue = (left.emailprimary || left.email || left.mail || '').toLowerCase();
          rightValue = (right.emailprimary || right.email || right.mail || '').toLowerCase();
        } else if (col === 'phone') {
          leftValue = left.phone || left.telephonenumber || '';
          rightValue = right.phone || right.telephonenumber || '';
        } else if (col === 'gradyear') {
          leftValue = String(left.currentgradyear || left.gradyear || '');
          rightValue = String(right.currentgradyear || right.gradyear || '');
        } else if (col === 'program') {
          leftValue = (left.program || '').toLowerCase();
          rightValue = (right.program || '').toLowerCase();
        } else if (col === 'title1') {
          leftValue = (left.title1 || left.title || '').toLowerCase();
          rightValue = (right.title1 || right.title || '').toLowerCase();
        } else if (col === 'facultytype') {
          leftValue = getFacultyType(left).toLowerCase();
          rightValue = getFacultyType(right).toLowerCase();
        }
        if (leftValue < rightValue) return dir === 'asc' ? -1 : 1;
        if (leftValue > rightValue) return dir === 'asc' ? 1 : -1;
        return 0;
      });
    }

    function buildHead(cols) {
      var tr = document.createElement('tr');
      cols.forEach(function (col) {
        var th = document.createElement('th');
        th.scope = 'col';
        if (col.key === 'photo') {
          th.style.width = '48px';
        } else if (col.sortKey) {
          th.style.cursor = 'pointer';
          th.style.userSelect = 'none';
          var arrow = state.sort.col === col.sortKey
            ? (state.sort.dir === 'asc' ? ' ▲' : ' ▼')
            : ' ⇅';
          th.textContent = col.label + arrow;
          (function (key) {
            th.addEventListener('click', function () {
              if (state.sort.col === key) {
                state.sort.dir = state.sort.dir === 'asc' ? 'desc' : 'asc';
              } else {
                state.sort.col = key;
                state.sort.dir = 'asc';
              }
              state.page = 1;
              renderCurrent();
            });
          }(col.sortKey));
        } else {
          th.textContent = col.label;
        }
        tr.appendChild(th);
      });
      theadEl.innerHTML = '';
      theadEl.appendChild(tr);
    }

    function buildBody(pageData, cols) {
      tbodyEl.innerHTML = '';
      pageData.forEach(function (person) {
        var tr = document.createElement('tr');
        tr.style.cursor = 'pointer';
        tr.addEventListener('click', function () { openProfile(person); });
        cols.forEach(function (col) {
          var td = document.createElement('td');
          if (col.key === 'photo') {
            var thumb = person.webthumburl || person.webthumbimage || person.thumburl || person.thumbnail || '';
            if (thumb) {
              var img = document.createElement('img');
              img.src = thumb;
              img.alt = '';
              img.className = 'rounded-circle';
              img.style.cssText = 'width:36px;height:36px;object-fit:cover;';
              img.onerror = function () { this.style.display = 'none'; };
              td.appendChild(img);
            }
          } else if (col.key === 'fullname') {
            if (state.group === 'faculty') {
              var degrees = person.combineddegrees || person.degrees || person.degree || '';
              var nameSpan = document.createElement('span');
              nameSpan.textContent = getName(person);
              td.appendChild(nameSpan);
              if (degrees) {
                var degreeSpan = document.createElement('span');
                degreeSpan.textContent = ', ' + degrees;
                degreeSpan.className = 'text-muted';
                td.appendChild(degreeSpan);
              }
            } else {
              td.textContent = getName(person);
            }
            td.className = 'fw-semibold';
          } else if (col.key === 'facultytype') {
            td.textContent = getFacultyType(person);
          } else if (col.key === 'title1') {
            td.textContent = person.title1 || person.title || '';
          } else if (col.key === 'email') {
            var email = person.emailprimary || person.email || person.mail || '';
            if (email) {
              var link = document.createElement('a');
              link.href = 'mailto:' + email;
              link.textContent = email;
              link.className = 'text-decoration-none';
              link.addEventListener('click', function (event) { event.stopPropagation(); });
              td.appendChild(link);
            }
          } else if (col.key === 'phone') {
            td.textContent = person.phone || person.telephonenumber || person.telephone || '';
          } else if (col.key === 'gradyear') {
            td.textContent = person.currentgradyear || person.gradyear || '';
          } else if (col.key === 'program') {
            td.textContent = person.program || '';
          }
          tr.appendChild(td);
        });
        tbodyEl.appendChild(tr);
      });
    }

    function buildPagination(total, page, pageSize) {
      var totalPages = Math.max(1, Math.ceil(total / pageSize));
      var from = Math.min((page - 1) * pageSize + 1, total);
      var to = Math.min(page * pageSize, total);
      pageInfoEl.textContent = total ? ('Showing ' + from + '–' + to + ' of ' + total) : '';
      pagCtrlEl.innerHTML = '';
      if (totalPages <= 1) return;

      var ul = document.createElement('ul');
      ul.className = 'pagination pagination-sm mb-0';

      function mkLi(label, target, disabled, active) {
        var li = document.createElement('li');
        li.className = 'page-item' + (disabled || active ? ' disabled' : '') + (active ? ' active' : '');
        var btn = document.createElement('button');
        btn.type = 'button';
        btn.className = 'page-link';
        btn.innerHTML = label;
        if (!disabled && !active) {
          btn.addEventListener('click', function () { state.page = target; renderCurrent(); });
        }
        li.appendChild(btn);
        return li;
      }

      ul.appendChild(mkLi('&laquo;', 1, page <= 1, false));
      ul.appendChild(mkLi('&lsaquo;', page - 1, page <= 1, false));
      var start = Math.max(1, page - 2);
      var end = Math.min(totalPages, start + 4);
      start = Math.max(1, end - 4);
      for (var index = start; index <= end; index++) {
        ul.appendChild(mkLi(String(index), index, false, index === page));
      }
      ul.appendChild(mkLi('&rsaquo;', page + 1, page >= totalPages, false));
      ul.appendChild(mkLi('&raquo;', totalPages, page >= totalPages, false));
      pagCtrlEl.appendChild(ul);
    }

    function makeInitialsAvatar(name) {
      var parts = (name || '').trim().split(/\s+/);
      var initials = parts.length >= 2
        ? (parts[0][0] + parts[parts.length - 1][0]).toUpperCase()
        : (parts[0] ? parts[0][0].toUpperCase() : '?');
      var div = document.createElement('div');
      div.className = 'rounded d-flex align-items-center justify-content-center mb-2 mx-auto text-white fw-semibold';
      div.style.cssText = 'width:64px;height:64px;font-size:20px;background-color:##6c757d;';
      div.textContent = initials;
      return div;
    }

    function buildCards(pageData) {
      cardGridEl.innerHTML = '';
      pageData.forEach(function (person) {
        var col = document.createElement('div');
        col.className = 'col-6 col-md-4 col-lg-3';
        var card = document.createElement('div');
        card.className = 'card h-100 shadow-sm';
        card.style.cursor = 'pointer';
        card.addEventListener('click', function () { openProfile(person); });
        var cardBody = document.createElement('div');
        cardBody.className = 'card-body text-center p-3';
        var thumb = person.webthumburl || person.webthumbimage || person.thumburl || person.thumbnail || '';
        if (thumb) {
          var img = document.createElement('img');
          img.src = thumb;
          img.alt = '';
          img.className = 'rounded mb-2 d-block mx-auto';
          img.style.cssText = 'width:64px;height:64px;object-fit:cover;';
          (function (imgEl, personName) {
            imgEl.onerror = function () { imgEl.replaceWith(makeInitialsAvatar(personName)); };
          }(img, getName(person)));
          cardBody.appendChild(img);
        } else {
          cardBody.appendChild(makeInitialsAvatar(getName(person)));
        }
        var nameEl = document.createElement('div');
        nameEl.className = 'fw-semibold small';
        nameEl.textContent = state.group === 'faculty' ? getNameWithDegrees(person) : getName(person);
        cardBody.appendChild(nameEl);
        var titleVal = person.title1 || person.title || person.jobtitle || '';
        if (isStudentGroup(state.group)) {
          var gradYear = person.currentgradyear || person.gradyear || '';
          titleVal = (person.program || '') + (gradYear ? ((person.program ? ' • ' : '') + 'Class of ' + gradYear) : '');
        }
        if (titleVal) {
          var titleEl = document.createElement('div');
          titleEl.className = 'text-muted small mt-1';
          titleEl.textContent = titleVal;
          cardBody.appendChild(titleEl);
        }
        var email = person.emailprimary || person.email || person.mail || '';
        if (email) {
          var emailWrap = document.createElement('div');
          emailWrap.className = 'small mt-1';
          var emailLink = document.createElement('a');
          emailLink.href = 'mailto:' + email;
          emailLink.className = 'text-decoration-none text-truncate d-block';
          emailLink.style.maxWidth = '100%';
          emailLink.textContent = email;
          emailLink.addEventListener('click', function (event) { event.stopPropagation(); });
          emailWrap.appendChild(emailLink);
          cardBody.appendChild(emailWrap);
        }
        var phone = person.phone || person.telephonenumber || person.telephone || '';
        if (phone) {
          var phoneEl = document.createElement('div');
          phoneEl.className = 'small text-muted mt-1';
          phoneEl.textContent = phone;
          cardBody.appendChild(phoneEl);
        }
        card.appendChild(cardBody);
        col.appendChild(card);
        cardGridEl.appendChild(col);
      });
    }

    function renderCurrent() {
      var term = state.search.toLowerCase();
      var filtered = state.allData.filter(function (person) {
        return !term || getLastName(getName(person)).indexOf(term) >= 0;
      });
      var sorted = sortData(filtered);
      var cols = colDefs(state.group);
      var totalPages = Math.max(1, Math.ceil(sorted.length / state.pageSize));
      if (state.page > totalPages) state.page = totalPages;
      var startIdx = (state.page - 1) * state.pageSize;
      var pageData = sorted.slice(startIdx, startIdx + state.pageSize);
      if (state.viewMode === 'cards') {
        tableEl.style.display = 'none';
        cardGridEl.style.display = '';
        buildCards(pageData);
        theadEl.innerHTML = '';
        tbodyEl.innerHTML = '';
      } else {
        tableEl.style.display = '';
        cardGridEl.style.display = 'none';
        buildHead(cols);
        buildBody(pageData, cols);
      }
      buildPagination(sorted.length, state.page, state.pageSize);
      wrapEl.style.display = '';
    }

    function openProfile(person) {
      var name = getName(person) || '(Unknown)';
      profileTitle.textContent = name;
      var thumb = person.webthumburl || person.webthumbimage || person.thumburl || '';
      var html = '';
      if (thumb) {
        html += '<div class="text-center mb-3"><img src="' + thumb + '" class="rounded-circle" style="width:80px;height:80px;object-fit:cover;" onerror="this.style.display=\'none\'"></div>';
      }
      function row(label, val) {
        return val ? '<dt class="col-sm-4 text-muted fw-normal">' + label + '</dt><dd class="col-sm-8">' + val + '</dd>' : '';
      }
      html += '<dl class="row mb-0">';
      html += row('Email', person.emailprimary || person.email || person.mail || '');
      html += row('Phone', person.phone || person.telephonenumber || '');
      html += row('Title', person.title1 || person.title || person.jobtitle || '');
      html += row('Type', getFacultyType(person) !== 'Faculty' || person.facultytype ? getFacultyType(person) : '');
      html += row('Degrees', person.combineddegrees || person.degrees || person.degree || '');
      html += row('Department', person.department || person.dept || '');
      html += row('Class of', person.currentgradyear || person.gradyear || '');
      html += row('Program', person.program || '');
      html += row('User ID', person.userid || '');
      html += '</dl>';
      profileBody.innerHTML = html;
      profileModal.show();
    }

    function loadDirectoryGroup(group, gradYear) {
      setStatus('info', 'Loading ' + group + '...');
      wrapEl.style.display = 'none';
      tbodyEl.innerHTML = '';

      var url = '/directory-data.cfm?group=' + encodeURIComponent(group);
      if (isStudentGroup(group) && gradYear) {
        url += '&gradyear=' + encodeURIComponent(gradYear);
      }

      fetch(url, { credentials: 'same-origin' })
        .then(function (res) { return res.json(); })
        .then(function (data) {
          var normalized = {};
          Object.keys(data).forEach(function (key) { normalized[key.toLowerCase()] = data[key]; });

          var items = normalized.items || [];
          state.group = group;
          state.allData = items.map(normPerson);
          state.search = '';
          state.gradYear = gradYear || '';
          searchEl.value = '';
          if (isStudentGroup(group)) {
            gradFilterWrapEl.style.display = '';
            gradFilterEl.value = state.gradYear;
          } else {
            gradFilterWrapEl.style.display = 'none';
            gradFilterEl.value = '';
          }
          state.page = 1;
          state.sort = { col: 'lastname', dir: 'asc' };
          state.pageSize = parseInt(pagSizeEl.value, 10) || 25;

          if (normalized.success) {
            if (items.length) {
              setStatus('success', group.charAt(0).toUpperCase() + group.slice(1) + ' - ' + items.length + ' members loaded.');
              renderCurrent();
            } else {
              setStatus('info', normalized.message || 'No members returned.');
            }
          } else {
            setStatus('error', normalized.message || 'Directory request failed.');
          }
        })
        .catch(function (err) {
          setStatus('error', 'Directory request failed: ' + err.message);
        });
    }

    if (profileModalCloseBtn) {
      profileModalCloseBtn.addEventListener('click', function () {
        profileModal.hide();
      });
    }

    viewTableBtn.addEventListener('click', function () {
      if (state.viewMode === 'table') return;
      state.viewMode = 'table';
      viewTableBtn.classList.add('active');
      viewCardsBtn.classList.remove('active');
      if (state.allData.length) renderCurrent();
    });

    viewCardsBtn.addEventListener('click', function () {
      if (state.viewMode === 'cards') return;
      state.viewMode = 'cards';
      viewCardsBtn.classList.add('active');
      viewTableBtn.classList.remove('active');
      if (state.allData.length) renderCurrent();
    });

    pagSizeEl.addEventListener('change', function () {
      state.pageSize = parseInt(pagSizeEl.value, 10) || 25;
      state.page = 1;
      if (state.allData.length) renderCurrent();
    });

    searchEl.addEventListener('input', function () {
      state.search = searchEl.value.trim();
      state.page = 1;
      if (state.allData.length) renderCurrent();
    });

    gradFilterEl.addEventListener('change', function () {
      state.gradYear = gradFilterEl.value;
      state.page = 1;
      if (!isStudentGroup(state.group)) return;
      if (!state.gradYear) {
        state.allData = [];
        wrapEl.style.display = 'none';
        tbodyEl.innerHTML = '';
        setStatus('info', 'Select class year to load ' + state.group + '.');
        return;
      }
      loadDirectoryGroup(state.group, state.gradYear);
    });

    document.querySelectorAll('.directory-group-btn').forEach(function (btn) {
      btn.addEventListener('click', function () {
        var group = btn.getAttribute('data-group');
        document.querySelectorAll('.directory-group-btn').forEach(function (currentBtn) { currentBtn.classList.remove('active'); });
        btn.classList.add('active');

        state.group = group;
        state.search = '';
        searchEl.value = '';
        state.page = 1;

        if (isStudentGroup(group)) {
          buildGradYearOptions(group);
          state.gradYear = '';
          gradFilterEl.value = '';
          gradFilterWrapEl.style.display = '';
          if (!gradFilterEl.value) {
            state.allData = [];
            wrapEl.style.display = 'none';
            tbodyEl.innerHTML = '';
            setStatus('info', 'Select class year to load ' + group + '.');
            return;
          }
          loadDirectoryGroup(group, gradFilterEl.value);
          return;
        }

        gradFilterWrapEl.style.display = 'none';
        gradFilterEl.value = '';
        state.gradYear = '';
        loadDirectoryGroup(group, '');
      });
    });

    }

    if (document.readyState === 'loading') {
      document.addEventListener('DOMContentLoaded', initDirectoryModule, { once: true });
    } else {
      initDirectoryModule();
    }
  }());
</script>
</cfoutput>