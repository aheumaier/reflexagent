import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["menu"]

  connect() {
    console.debug("MobileMenuController connected")
  }

  disconnect() {
    console.debug("MobileMenuController disconnected")
  }

  toggle(event) {
    console.debug("MobileMenuController toggle called")
    
    // Prevent default link behavior
    event.preventDefault()
    
    // Toggle the hidden class
    this.menuTarget.classList.toggle("hidden")
    
    // Update aria-expanded attribute
    const button = event.currentTarget
    const expanded = button.getAttribute("aria-expanded") === "true" || false
    button.setAttribute("aria-expanded", !expanded)
    
    console.debug(`Mobile menu is now ${this.menuTarget.classList.contains("hidden") ? "hidden" : "visible"}`)
  }
} 