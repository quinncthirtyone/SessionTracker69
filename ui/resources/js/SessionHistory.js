$(document).ready(function() {
    // This script initializes the DataTable for the session history page,
    // making the table of recent sessions sortable and searchable.

    const tableBody = $('#sessionHistoryTable tbody');

    if (!sessionData || !Array.isArray(sessionData)) {
        console.error("Session data is missing or not in the correct format.");
        return;
    }

    const url = window.location.pathname;
    const match = url.match(/_(\d+)\.html$/);
    const currentProfileId = match ? parseInt(match[1], 10) : null;

    // Loop through each session record passed from the PowerShell script
    sessionData.forEach(session => {
        // Sanitize data before inserting it into the DOM to prevent XSS attacks
        const safeGameName = DOMPurify.sanitize(session.GameName);
        const safeIconPath = DOMPurify.sanitize(session.IconPath);
        const safeDuration = DOMPurify.sanitize(session.Duration);
        const safeStartDate = DOMPurify.sanitize(session.StartDate);
        const safeStartTime = DOMPurify.sanitize(session.StartTime);
        const safeEndTime = DOMPurify.sanitize(session.EndTime);

        let actionsCell = '<td><button class="delete-button" data-session-id="${session.Id}">Delete</button>';
        if (profileData.length > 1 && currentProfileId) {
            const otherProfile = profileData.find(p => p.id !== currentProfileId);
            if (otherProfile) {
                actionsCell += `<button class="switch-profile-button" data-session-id="${session.Id}" data-new-profile-id="${otherProfile.id}">Switch to ${otherProfile.name}</button>`;
            }
        }
        actionsCell += '</td>';

        actionsCell = actionsCell.replace(/\${session.Id}/g, session.Id);


        // Create the HTML for the new table row
        const row = `
            <tr>
                <td>
                    <div class="game-cell">
                        <img src="${safeIconPath}" class="game-icon" onerror="this.onerror=null;this.src='resources/images/default.png';">
                        <span>${safeGameName}</span>
                    </div>
                </td>
                <td>${safeDuration}</td>
                <td>${safeStartDate}</td>
                <td>${safeStartTime}</td>
                <td>${safeEndTime}</td>
                ${actionsCell}
            </tr>
        `;
        // Append the new row to the table body
        tableBody.append(row);
    });

    // Initialize the DataTable plugin on the table
    $('#sessionHistoryTable').DataTable({
        // Set the default sort order to descending by date, then by time
        "order": [[ 2, "desc" ], [3, "desc"]],
        "pageLength": 25,
        "lengthMenu": [ [10, 25, 50, -1], [10, 25, 50, "All"] ],
        "columnDefs": [
            // Define properties for each column
            { "targets": 0, "orderable": true, "searchable": true }, // Game
            { "targets": 1, "orderable": false, "searchable": false }, // Duration
            { "targets": 2, "orderable": true, "searchable": true }, // Date
            { "targets": 3, "orderable": true, "searchable": false },  // Start Time
            { "targets": 4, "orderable": true, "searchable": false },  // End Time
            { "targets": 5, "orderable": false, "searchable": false } // Actions
        ]
    });

    $('#sessionHistoryTable').on('click', '.delete-button', function() {
        const sessionId = $(this).data('session-id');
        if (confirm('Are you sure you want to delete this session?')) {
            fetch(`http://localhost:8088/remove-session/${sessionId}`)
                .then(() => location.reload());
        }
    });

    $('#sessionHistoryTable').on('click', '.switch-profile-button', function() {
        const sessionId = $(this).data('session-id');
        const newProfileId = $(this).data('new-profile-id');
        if (confirm(`Are you sure you want to switch this session to the other profile?`)) {
            fetch(`http://localhost:8088/switch-session-profile/${sessionId}/${newProfileId}`)
                .then(() => location.reload());
        }
    });
});
