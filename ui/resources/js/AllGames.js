$(document).ready(function () {
    const tableBody = $('#games-table tbody');

    if (!gamesData || !Array.isArray(gamesData.games)) {
        console.error("Games data is missing or not in the correct format.");
        return;
    }

    gamesData.games.forEach(game => {
        const safeIconPath = DOMPurify.sanitize(game.IconPath);
        const safeName = DOMPurify.sanitize(game.Name);
        const safePlaytime = DOMPurify.sanitize(game.Playtime);
        const safeSessionCount = DOMPurify.sanitize(game.SessionCount);
        const safeStatusText = DOMPurify.sanitize(game.StatusText);
        const safeStatusIcon = DOMPurify.sanitize(game.StatusIcon);
        const safeLastPlayedOn = DOMPurify.sanitize(game.LastPlayedOn);

        const row = `
            <tr>
                <td><img src="${safeIconPath}" class="game-icon" onerror="this.onerror=null;this.src='resources/images/default.png';"></td>
                <td>${safeName}</td>
                <td>${safePlaytime}</td>
                <td>${safeSessionCount}</td>
                <td><div>${safeStatusText}</div><img src="${safeStatusIcon}"></td>
                <td>${safeLastPlayedOn}</td>
            </tr>
        `;
        tableBody.append(row);
    });

    $('table').DataTable({
        columnDefs: [
          {
            targets: 2,
            className: "playtimegradient",
            render: function (data, type, row, meta) {
              if (type === "display" || type === "filter") {
                var playtime = parseInt(data);
                if (isNaN(playtime)) {
                    playtime = 0;
                }
                var hours = Math.floor(playtime / 60);
                var minutes = playtime % 60;
                return hours + " Hr " + minutes + " Min";
              }
              return data;
            },
            createdCell: function (td, cellData, rowData, row, col) {
              var maxPlayTime = gamesData.maxPlaytime;
              var playtime = parseInt(cellData);
              if (isNaN(playtime)) {
                  playtime = 0;
              }

              var percentage = 0;
              if (maxPlayTime > 0) {
                percentage = (
                  (playtime / maxPlayTime) *
                  95
                ).toFixed(2);
              }
              $(td).css("background-size", percentage + "% 85%");
            },
          },
          {
            targets: 5,
            render: function (data, type, row, meta) {
              if (type === "display" || type === "filter") {
                var utcSeconds = parseInt(data);
                if (isNaN(utcSeconds) || utcSeconds === 0) {
                    return "N/A";
                }
                var date = new Date(0);
                date.setUTCSeconds(utcSeconds);
                return date.toLocaleDateString(undefined, {
                  year: "numeric",
                  month: "long",
                  day: "numeric",
                });
              }
              return data;
            },
          },
        ],
        order: [
          [5, "desc"],
        ],
        ordering: true,
        paging: "numbers",
        pageLength: 9,
        lengthChange: false,
        searching: true,
    });

    const wrapper = $("#games-table_wrapper")[0];
    const allGamesDiv = document.createElement('div');
    allGamesDiv.id = 'AllGames';
    allGamesDiv.innerText = 'All Games\n' + gamesData.totalGameCount;
    wrapper.insertAdjacentElement('afterbegin', allGamesDiv);

    const totalPlaytimeDiv = document.createElement('div');
    totalPlaytimeDiv.id = 'TotalPlaytime';
    totalPlaytimeDiv.innerText = 'Total Playtime\n' + gamesData.totalPlaytime;
    wrapper.insertAdjacentElement('afterbegin', totalPlaytimeDiv);

    document
        .getElementById("Toggle-Pagination")
        .addEventListener("click", () => {
        if ($("table").DataTable().page.len() === 9) {
            document.getElementById("Toggle-Pagination").innerText =
            "Paginate";
            $("table").DataTable().page.len(-1).draw();
        } else {
            document.getElementById("Toggle-Pagination").innerText =
            "Show All";
            $("table").DataTable().page.len(9).draw();
        }
    });

    $("#games-table-container").show();
});
