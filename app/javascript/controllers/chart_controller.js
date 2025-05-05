import { Controller } from "@hotwired/stimulus"
import { Chart, registerables } from "chart.js";

// Register all Chart.js components
Chart.register(...registerables);

// Log Chart.js availability in module scope
console.log("Chart controller module loaded, Chart.js imported and registered:", Chart ? "YES" : "NO")

// Connects to data-controller="chart"
export default class extends Controller {
  static targets = ["canvas"]
  static values = {
    type: String,
    data: Object,
    options: Object
  }
  
  connect() {
    console.log("Chart controller connected to", this.element)
    
    if (!this.hasCanvasTarget) {
      console.error("No canvas target found for chart controller")
      this.element.innerHTML = `<div class="text-red-500 p-4 text-center">Error: No canvas target found</div>`
      return
    }
    
    // Initialize with a small delay to ensure DOM is ready
    setTimeout(() => this.initializeChart(), 100)
  }
  
  disconnect() {
    // Clean up chart instance if it exists
    if (this.chart) {
      this.chart.destroy()
      this.chart = null
    }
  }
  
  initializeChart() {
    // If we already have a chart, destroy it
    if (this.chart) {
      this.chart.destroy()
    }
    
    try {
      const canvas = this.canvasTarget
      const canvasId = canvas.id || `chart-${Math.random().toString(36).substring(2, 9)}`
      
      // If canvas doesn't have an ID, assign one for tracking
      if (!canvas.id) {
        canvas.id = canvasId
      }
      
      const ctx = canvas.getContext('2d')
      
      if (!ctx) {
        console.error("Could not get 2d context from canvas")
        return
      }
      
      // Check if chart was already initialized outside of this controller
      if (canvas.hasAttribute('data-chart-initialized') || 
          canvas.__chartInstance || 
          (window.initializedCharts && window.initializedCharts[canvasId])) {
        console.log(`Chart ${canvasId} already initialized elsewhere, skipping stimulus initialization`)
        return
      }
      
      // Get chart type from element or default to line
      const type = this.element.getAttribute('data-chart-type-value') || 'line'
      
      // Get chart data from Stimulus values or data attributes
      let data
      if (this.hasDataValue) {
        console.log("Using data from Stimulus value")
        data = this.dataValue
      } else {
        // Fallback to direct attribute
        try {
          console.log("Trying to get data from direct attribute")
          const dataStr = this.canvasTarget.getAttribute('data-chart-data-value')
          if (dataStr) {
            data = JSON.parse(dataStr)
            console.log("Parsed data from attribute:", data)
          } else {
            console.error("No data found in data-chart-data-value attribute")
            data = null
          }
        } catch (e) {
          console.error("Error parsing chart data:", e)
          data = null
        }
      }
      
      // Use default data if none available
      if (!data || !data.datasets || data.datasets.length === 0) {
        console.log("No valid data found, using default sample data")
        data = {
          labels: ['Sample 1', 'Sample 2', 'Sample 3', 'Sample 4', 'Sample 5'],
          datasets: [{
            label: 'Sample Data',
            data: [12, 19, 3, 5, 2],
            backgroundColor: 'rgba(79, 70, 229, 0.2)',
            borderColor: 'rgba(79, 70, 229, 1)',
            borderWidth: 2,
          }]
        }
      }
      
      // Get options from Stimulus values or data attributes
      let options
      if (this.hasOptionsValue) {
        console.log("Using options from Stimulus value")
        options = this.optionsValue
      } else {
        // Fallback to direct attribute
        try {
          console.log("Trying to get options from direct attribute")
          const optionsStr = this.canvasTarget.getAttribute('data-chart-options-value')
          if (optionsStr) {
            options = JSON.parse(optionsStr)
            console.log("Parsed options from attribute:", options)
          } else {
            console.log("No options found in data-chart-options-value attribute")
            options = null
          }
        } catch (e) {
          console.error("Error parsing chart options:", e)
          options = null
        }
      }
      
      // Default options if none available
      if (!options) {
        console.log("Using default options")
        options = {
          responsive: true,
          maintainAspectRatio: false,
          scales: {
            y: {
              beginAtZero: true
            }
          }
        }
      }
      
      // More detailed logging about what we're creating
      console.log(`Creating ${type} chart for canvas ${canvasId}`, {
        data: {
          labels: data.labels ? `${data.labels.length} labels` : 'No labels',
          datasets: data.datasets ? `${data.datasets.length} datasets` : 'No datasets' 
        },
        options: {
          responsive: options.responsive,
          maintainAspectRatio: options.maintainAspectRatio,
          scales: options.scales ? 'Custom scales' : 'Default scales'
        }
      })
      
      // Mark chart as initialized before creating to prevent double initialization
      window.initializedCharts = window.initializedCharts || {}
      window.initializedCharts[canvasId] = true
      canvas.setAttribute('data-chart-initialized', 'true')
      
      // Make canvas visible with a border for debugging
      canvas.style.border = '1px solid #eee'
      
      // Use Chart with proper initialization
      this.chart = new Chart(ctx, {
        type,
        data,
        options
      })
      
      // Store instance on canvas for reference
      canvas.__chartInstance = this.chart
      
      console.log(`${type} chart initialized successfully with id: ${canvasId}`)
    } catch (error) {
      console.error(`Error initializing chart: ${error.message}`, error)
      this.element.innerHTML = `<div class="text-red-500 p-4">Error creating chart: ${error.message}</div>`
    }
  }
  
  // Action method to update chart data
  updateData(event) {
    if (!this.chart) return
    
    const newData = event.detail
    if (!newData) return
    
    this.chart.data = newData
    this.chart.update()
  }
} 