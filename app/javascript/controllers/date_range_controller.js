import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["dropdown"]
  
  connect() {
    console.debug("DateRangeController connected")
    this.closeHandler = this.close.bind(this)
    document.addEventListener('click', this.closeHandler)
  }
  
  disconnect() {
    console.debug("DateRangeController disconnected")
    document.removeEventListener('click', this.closeHandler)
  }
  
  open(event) {
    console.debug("DateRangeController open called")
    event.stopPropagation()
    
    // Create the dropdown if it doesn't exist
    if (!this.hasDropdownTarget) {
      console.debug("Creating dropdown element")
      const dropdown = this.createDropdown()
      this.element.appendChild(dropdown)
    }
    
    this.dropdownTarget.classList.toggle('hidden')
  }
  
  close(event) {
    if (this.hasDropdownTarget && !this.element.contains(event.target)) {
      console.debug("DateRangeController closing dropdown")
      this.dropdownTarget.classList.add('hidden')
    }
  }
  
  createDropdown() {
    console.debug("DateRangeController creating dropdown")
    const dropdown = document.createElement('div')
    dropdown.setAttribute('data-date-range-target', 'dropdown')
    dropdown.className = 'absolute z-10 mt-2 bg-white rounded-md shadow-lg p-4 hidden'
    dropdown.style.right = '0'
    dropdown.style.minWidth = '300px'
    
    dropdown.innerHTML = `
      <div class="space-y-4">
        <div>
          <label class="block text-sm font-medium text-gray-700 mb-1">Start Date</label>
          <input type="date" class="block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 sm:text-sm" />
        </div>
        <div>
          <label class="block text-sm font-medium text-gray-700 mb-1">End Date</label>
          <input type="date" class="block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 sm:text-sm" />
        </div>
        <div class="flex justify-end space-x-2">
          <button type="button" class="inline-flex items-center rounded-md border border-gray-300 bg-white px-3 py-2 text-sm font-medium text-gray-700 shadow-sm hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-indigo-500 focus:ring-offset-2">Cancel</button>
          <button type="button" class="inline-flex items-center rounded-md border border-transparent bg-indigo-600 px-3 py-2 text-sm font-medium text-white shadow-sm hover:bg-indigo-700 focus:outline-none focus:ring-2 focus:ring-indigo-500 focus:ring-offset-2">Apply</button>
        </div>
      </div>
    `
    
    return dropdown
  }
} 