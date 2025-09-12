/*global ChartDataLabels, Chart, chartTitleConfig, gamingData*/
/*from chart.js, common.js and html templates*/

function calculateStepSize(maxMinutes) {
  if (maxMinutes <= 0) {
      return 60; // Default to 1 hour step
  }

  const maxHours = maxMinutes / 60;
  const maxTicks = 10;

  // We want to find a step that is a whole number of hours.
  // And divides the range into less than `maxTicks` intervals.
  let stepInHours = Math.ceil(maxHours / (maxTicks - 1));

  // If the step is 1, we don't need to do anything fancy.
  if (stepInHours <= 1) {
      return 60; // 1 hour in minutes
  }
  
  // Now, let's make it a "nice" number (2, 5, or a multiple of 5)
  if (stepInHours > 5) {
      // Round up to the nearest multiple of 5
      stepInHours = Math.ceil(stepInHours / 5) * 5;
  } else if (stepInHours > 2) {
      stepInHours = 5;
  } else {
      stepInHours = 2;
  }

  return stepInHours * 60; // Convert back to minutes
}

let mostPlayedChart;

function updateMostPlayedChart(gameCount) {
  // Ensure gamingData is available
  if (typeof gamingData === 'undefined' || gamingData.length === 0) {
    return;
  }

  const labels = [];
  const data = [];
  const colors = [];

  const displayData = gamingData.slice(0, gameCount);

  for (const game of displayData) {
    labels.push(game.name);
    const hours = Math.floor(game.time / 60);
    const minutes = game.time % 60;
    data.push(game.time); // Keep data in minutes for processing
    colors.push(game.color_hex || '#cccccc'); // Use default color if null
  }

  if (mostPlayedChart) {
    mostPlayedChart.destroy();
  }

  const maxTime = Math.max(...data);
  const stepSize = calculateStepSize(maxTime);

  const ctx = document.getElementById("most-played-chart-canvas").getContext("2d");

  mostPlayedChart = new Chart(ctx, {
    type: "bar",
    plugins: [ChartDataLabels],
    data: {
      labels: labels,
      datasets: [
        {
          label: "Playtime",
          data: data,
          backgroundColor: colors,
          borderWidth: 1,
        },
      ],
    },
    options: {
      responsive: true,
      maintainAspectRatio: false,
      indexAxis: "y",
      layout: {
        padding: {
          right: 50,
        },
      },
      scales: {
        y: {
          ticks: {
            autoSkip: false,
            font: {
              size: 14,
            }
          },
        },
        x: {
          type: "linear",
          title: chartTitleConfig("Playtime (Hours)", 15),
          ticks: {
            stepSize: stepSize,
            precision: 0,
            callback: function(value) {
                // Display ticks as hours
                return Math.floor(value / 60) + "h";
            }
          }
        },
      },
      plugins: {
        legend: {
          display: false,
        },
        tooltip: {
          enabled: true, // Enable tooltips for better UX
          callbacks: {
            label: function(context) {
              const value = context.raw;
              const hours = Math.floor(value / 60);
              const minutes = value % 60;
              return `${hours}h ${minutes}m`;
            }
          }
        },
        datalabels: {
          anchor: "end",
          align: "right",
          formatter: function (value) {
            if (value === 0) return "";
            const hours = Math.floor(value / 60);
            const minutes = value % 60;
            return `${hours}h ${minutes}m`;
          },
          color: "#000000",
          font: {
            family: "monospace",
          },
        },
      }
    },
  });
}
