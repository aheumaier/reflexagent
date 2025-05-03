import { Controller } from "@hotwired/stimulus"
import Chart from "chart.js/auto"

// Connects to data-controller="chart"
export default class extends Controller {
  static targets = ["canvas"]
  static values = {
    type: String,
    data: Object,
    options: Object
  }
  
  connect() {
    console.log("Chart controller connected")
    
    if (!this.hasCanvasTarget) {
      console.warn("No canvas target found for chart controller")
      return
    }
    
    // Check if Chart.js is available
    if (typeof Chart === 'undefined') {
      console.error("Chart.js is not available - please include the Chart.js library")
      this.element.innerHTML = `<div class="text-red-500 p-4 text-center">Chart.js library not loaded</div>`
      return
    }
    
    this.initializeChart()
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
      const ctx = this.canvasTarget.getContext('2d')
      
      // Get chart type or default to line
      const type = this.typeValue || 'line'
      
      // Get chart data or use default empty data
      const data = this.hasDataValue ? this.dataValue : {
        labels: ['No Data'],
        datasets: [{
          label: 'No Data Available',
          data: [0],
          backgroundColor: 'rgba(200, 200, 200, 0.2)',
          borderColor: 'rgba(200, 200, 200, 1)',
        }]
      }
      
      // Get chart options or use defaults
      const options = this.hasOptionsValue ? this.optionsValue : {
        responsive: true,
        maintainAspectRatio: false,
        scales: {
          y: {
            beginAtZero: true
          }
        }
      }
      
      // Create the chart
      this.chart = new Chart(ctx, {
        type,
        data,
        options
      })
      
      console.log(`${type} chart initialized with Stimulus`)
    } catch (error) {
      console.error(`Error initializing chart: ${error.message}`)
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