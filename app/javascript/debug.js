// Simple diagnostic file
console.log('debug.js loaded - confirming esbuild is working correctly');

// Function to check Stimulus loading
window.checkStimulusLoading = function() {
  console.log('Manually checking Stimulus loading...');
  
  // Check if the Stimulus application is defined
  if (window.Stimulus) {
    console.log('Stimulus is available globally - direct check');
  } else {
    console.log('window.Stimulus not found');
  }
  
  // Check for the presence of data-controller elements
  const controllers = document.querySelectorAll('[data-controller]');
  console.log(`Found ${controllers.length} elements with data-controller attributes`);
  
  controllers.forEach(el => {
    const controllerName = el.getAttribute('data-controller');
    console.log(`Element ${el.tagName} has controller: ${controllerName}`);
    
    // Test if clicking the controller works
    if (controllerName === 'mobile-menu' || controllerName === 'date-range') {
      console.log(`Found clickable controller: ${controllerName} - try interacting with it`);
    }
  });
}

// Auto-run check after a delay
setTimeout(window.checkStimulusLoading, 1000);

// Attach click debugging to the document
document.addEventListener('click', function(event) {
  const target = event.target;
  console.log(`Clicked on ${target.tagName}#${target.id || 'no-id'}`);
  
  // Check if it's a controller element
  const controller = target.closest('[data-controller]');
  if (controller) {
    console.log(`This is or is within a ${controller.getAttribute('data-controller')} controller element`);
  }
});

// Debug for date filtering
document.addEventListener('turbo:before-visit', function(event) {
  console.log('Turbo navigation starting to:', event.detail.url);
  // Check if it's a date filter change
  if (event.detail.url.includes('days=')) {
    console.log('Date filter changing in URL:', event.detail.url);
  }
});

document.addEventListener('turbo:load', function(event) {
  console.log('Page loaded via Turbo');
  
  // Check for date filter buttons
  const dateFilterButtons = document.querySelectorAll('a[href*="days="]');
  console.log(`Found ${dateFilterButtons.length} date filter buttons`);
  
  dateFilterButtons.forEach(button => {
    console.log(`Date filter button: ${button.textContent.trim()} -> ${button.getAttribute('href')}`);
    
    // Check if it appears to be the active one based on style
    const isActive = button.style.backgroundColor === 'rgb(67, 56, 202)' || 
                     button.style.backgroundColor === '#4338ca';
    if (isActive) {
      console.log(`Active date filter appears to be: ${button.textContent.trim()}`);
    }
  });
}); 