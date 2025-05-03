// Entry point for the build script in your package.json
import "@hotwired/turbo-rails"
import { Application } from "@hotwired/stimulus"
import "./controllers"
import "./debug" // Import debug helpers
import Chart from 'chart.js/auto'

// Make Chart.js available globally for debugging
window.Chart = Chart;

// Make Stimulus available globally for debugging
window.Stimulus = Application;

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
    console.debug("Chart.js is available globally")
  } else {
    console.debug("Chart.js is not available globally (this is expected if using ES modules)")
  }
})

// Debug Turbo events
document.addEventListener("turbo:load", () => {
  console.debug("turbo:load event fired - page has loaded via Turbo")
})

document.addEventListener("turbo:before-visit", () => {
  console.debug("turbo:before-visit event fired - about to navigate away")
})
