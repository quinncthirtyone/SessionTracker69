/* global DOMPurify, sessionData, profileData */
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
        const safeType = DOMPurify.sanitize(session.Type);

        const row = document.createElement('tr');
        row.dataset.sessionId = session.Id;

        // Game Cell
        const gameCell = document.createElement('td');
        if (safeType === 'Idle') {
            gameCell.className = 'idle-session';
        } else {
            gameCell.className = 'active-session';
        }

        const gameCellDiv = document.createElement('div');
        gameCellDiv.className = 'game-cell';

        const gameIcon = document.createElement('img');
        gameIcon.src = safeIconPath;
        gameIcon.className = 'game-icon';
        gameIcon.onerror = function() { this.onerror=null; this.src='resources/images/default.png'; };
        gameCellDiv.appendChild(gameIcon);

        const gameNameSpan = document.createElement('span');
        gameNameSpan.textContent = safeGameName;
        gameCellDiv.appendChild(gameNameSpan);
        gameCell.appendChild(gameCellDiv);
        row.appendChild(gameCell);

        // Data Cells
        const durationCell = document.createElement('td');
        durationCell.textContent = safeDuration;
        row.appendChild(durationCell);

        const startDateCell = document.createElement('td');
        startDateCell.textContent = safeStartDate;
        row.appendChild(startDateCell);

        const startTimeCell = document.createElement('td');
        startTimeCell.textContent = safeStartTime;
        row.appendChild(startTimeCell);

        const endTimeCell = document.createElement('td');
        endTimeCell.textContent = safeEndTime;
        row.appendChild(endTimeCell);

        // Actions Cell
        const actionsCell = document.createElement('td');
        actionsCell.className = 'action-buttons';

        const originalActionsDiv = document.createElement('div');
        originalActionsDiv.className = 'original-actions';

        const editButton = document.createElement('button');
        editButton.className = 'edit-button';
        editButton.dataset.sessionId = session.Id;
        editButton.textContent = 'Edit';
        originalActionsDiv.appendChild(editButton);

        if (safeType === 'Idle') {
            const convertButton = document.createElement('button');
            convertButton.className = 'convert-idle-button';
            convertButton.dataset.sessionId = session.Id;
            convertButton.textContent = 'Convert to Active';
            originalActionsDiv.appendChild(convertButton);

            const deleteIdleButton = document.createElement('button');
            deleteIdleButton.className = 'delete-idle-button';
            deleteIdleButton.dataset.sessionId = session.Id;
            deleteIdleButton.textContent = 'Delete';
            originalActionsDiv.appendChild(deleteIdleButton);
        } else { // Active session
            if (profileData.length > 1 && currentProfileId) {
                const otherProfile = profileData.find(p => p.id !== currentProfileId);
                if (otherProfile) {
                    const switchProfileButton = document.createElement('button');
                    switchProfileButton.className = 'switch-profile-button';
                    switchProfileButton.dataset.sessionId = session.Id;
                    switchProfileButton.dataset.newProfileId = otherProfile.id;
                    switchProfileButton.textContent = `Switch to ${otherProfile.name}`;
                    originalActionsDiv.appendChild(switchProfileButton);
                }
            }
            const deleteButton = document.createElement('button');
            deleteButton.className = 'delete-button';
            deleteButton.dataset.sessionId = session.Id;
            deleteButton.textContent = 'Delete';
            originalActionsDiv.appendChild(deleteButton);
        }
        actionsCell.appendChild(originalActionsDiv);
        row.appendChild(actionsCell);

        // Append the new row to the table body
        tableBody.append(row);
    });

    // Initialize the DataTable plugin on the table
    $('#sessionHistoryTable').DataTable({
        // Set the default sort order to descending by date, then by time
        "order": [[ 2, "desc" ], [3, "desc"]],
        "pageLength": 15,
        "dom": '<"filter-container"f>rtip',
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

    function parseDuration(durationStr) {
        let hours = 0;
        let minutes = 0;
        if (durationStr.includes('h')) {
            const parts = durationStr.split('h');
            hours = parseInt(parts[0], 10) || 0;
            if (parts[1] && parts[1].includes('m')) {
                minutes = parseInt(parts[1].replace('m', '').trim(), 10) || 0;
            }
        } else if (durationStr.includes('m')) {
            minutes = parseInt(durationStr.replace('m', '').trim(), 10) || 0;
        }
        return { hours, minutes };
    }

    function exitEditMode(row) {
        row.removeClass('is-editing');

        // Restore Game Name
        const gameCell = row.find('td:first-child .game-cell');
        const originalGameName = row.data('original-game-name');
        if (originalGameName) {
            // Reconstruct the original cell content with the image
            const iconSrc = gameCell.find('img').attr('src');
            gameCell.html(`<img src="${iconSrc}" class="game-icon" onerror="this.onerror=null;this.src='resources/images/default.png';"> <span>${originalGameName}</span>`);
            row.removeData('original-game-name');
        }


        // Restore Duration
        const durationCell = row.find('td:nth-child(2)');
        const originalDuration = row.data('original-duration');
        if (originalDuration) {
            durationCell.text(originalDuration);
            row.removeData('original-duration');
        }

        // Restore Action Buttons
        row.find('.action-buttons .save-button, .action-buttons .cancel-button').remove();
        row.find('.action-buttons .original-actions').show();
    }

    $('#sessionHistoryTable').on('click', '.edit-button', function() {
        const row = $(this).closest('tr');
        if (row.hasClass('is-editing')) {
            return;
        }
        row.addClass('is-editing');

        // Game Name
        const gameCell = row.find('td:first-child .game-cell');
        const originalGameName = gameCell.find('span').text();
        row.data('original-game-name', originalGameName);
        const iconSrc = gameCell.find('img').attr('src');
        gameCell.html(`<img src="${iconSrc}" class="game-icon" onerror="this.onerror=null;this.src='resources/images/default.png';"> <input type="text" class="game-name-input" value="${originalGameName}">`);


        // Duration
        const durationCell = row.find('td:nth-child(2)');
        const originalDuration = durationCell.text();
        row.data('original-duration', originalDuration);
        const { hours, minutes } = parseDuration(originalDuration);
        const durationEditControls = `
            <input type="number" class="duration-hours-input" value="${hours}" min="0" style="width: 40px;"> h
            <input type="number" class="duration-minutes-input" value="${minutes}" min="0" max="59" style="width: 40px;"> m
        `;
        durationCell.html(durationEditControls);

        // Action Buttons
        const actionsCell = row.find('.action-buttons');
        actionsCell.find('.original-actions').hide();
        actionsCell.append(`
            <button class="save-button" style="margin-left: 10px;">Save</button>
            <button class="cancel-button" style="margin-left: 5px;">Cancel</button>
        `);
    });

    $('#sessionHistoryTable').on('click', '.cancel-button', function() {
        const row = $(this).closest('tr');
        exitEditMode(row);
    });

    $('#sessionHistoryTable').on('click', '.save-button', function() {
        const row = $(this).closest('tr');
        row.removeClass('is-editing');
        const sessionId = row.data('session-id');

        // Get New Game Name
        const newGameName = row.find('.game-name-input').val();

        // Get New Duration
        const hours = parseInt(row.find('.duration-hours-input').val(), 10) || 0;
        const minutes = parseInt(row.find('.duration-minutes-input').val(), 10) || 0;
        const newDuration = (hours * 60) + minutes;

        fetch(`http://localhost:8088/update-session`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                sessionId: sessionId,
                newGameName: newGameName,
                newDuration: newDuration
            })
        })
        .then(response => {
            if (response.ok) {
                // Update the cell content without a full reload
                const gameCell = row.find('td:first-child .game-cell');
                const iconSrc = gameCell.find('img').attr('src');
                gameCell.html(`<img src="${iconSrc}" class="game-icon" onerror="this.onerror=null;this.src='resources/images/default.png';"> <span>${newGameName}</span>`);

                const durationCell = row.find('td:nth-child(2)');
                durationCell.text(`${Math.floor(newDuration / 60)}h ${newDuration % 60}m`);

                exitEditMode(row);
                // Optionally, show a success message
            } else {
                alert('Failed to update session. Please check the game name exists.');
                exitEditMode(row); // Also exit edit mode on failure
            }
        })
        .catch(error => {
            console.error('Error updating session:', error);
            alert('An error occurred while updating the session.');
            exitEditMode(row); // Also exit edit mode on failure
        });
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

    $('#sessionHistoryTable').on('click', '.convert-idle-button', function() {
        const sessionId = $(this).data('session-id');
        if (confirm('Are you sure you want to convert this idle session to active time?')) {
            fetch(`http://localhost:8088/convert-idle-session/${sessionId}`)
                .then(() => location.reload());
        }
    });

    $('#sessionHistoryTable').on('click', '.delete-idle-button', function() {
        const sessionId = $(this).data('session-id');
        if (confirm('Are you sure you want to delete this idle session?')) {
            fetch(`http://localhost:8088/delete-idle-session/${sessionId}`)
                .then(() => location.reload());
        }
    });
});
