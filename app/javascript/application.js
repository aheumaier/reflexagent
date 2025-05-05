// Entry point for the build script in your package.json
import "@hotwired/turbo-rails"
import { Application } from "@hotwired/stimulus"
import "./controllers"
import "./debug" // Import debug helpers
import Chart from 'chart.js/auto'

// Make Chart.js available globally for debugging
window.Chart = Chart;
console.log("Application.js: Chart.js set to window.Chart", Chart ? "YES" : "NO");

// Make Stimulus available globally for debugging
window.Stimulus = Application;

// Initialize tracking for charts
window.initializedCharts = window.initializedCharts || {};

// Debug initialization
document.addEventListener("DOMContentLoaded", () => {
  console.debug("DOMContentLoaded event fired")
  console.debug("Checking for Stimulus controllers...")
  
  // Log all elements with data-controller attributes
  const controllerElements = document.querySelectorAll("[data-controller]")
  console.debug(`Found ${controllerElements.length} elements with data-controller attributes:`)
  
  controllerElements.forEach(el => {
    const controllers = el.getAttribute("data-controller").split(" ")
    console.debug(`Element: ${el.tagName}#${el.id || "no-id"}, Controllers: ${controllers.join(", ")}`)
  })
  
  // Check for Chart.js
  if (typeof Chart !== 'undefined') {
    console.debug("Chart.js is available as module import")
  } else {
    console.debug("Chart.js module import not available!")
  }
  
  // Check for global Chart.js
  if (window.Chart) {
    console.debug("Chart.js is available globally as window.Chart")
  } else {
    console.error("Chart.js is NOT available globally")
  }
})

// Debug Turbo events
document.addEventListener("turbo:load", () => {
  console.debug("turbo:load event fired - page has loaded via Turbo")
})

document.addEventListener("turbo:before-visit", () => {
  console.debug("turbo:before-visit event fired - about to navigate away")
})
