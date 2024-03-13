document.addEventListener('DOMContentLoaded', function() {
    // Select all buttons
    const buttons = document.querySelectorAll('.btn');

    buttons.forEach(button => {
        button.addEventListener('mousedown', function() {
            this.classList.add('clicked');
            // Optional: Remove the class after some time
            setTimeout(() => {
                this.classList.remove('clicked');
            }, 200); // 200 milliseconds
        });
    });
});
document.addEventListener('DOMContentLoaded', function() {
    var textarea = document.getElementById('question');
    textarea.addEventListener('keydown', function(e) {
        // Check if Enter was pressed without Shift key
        if (e.key === 'Enter' && !e.shiftKey) {
            e.preventDefault(); // Prevent the default action (inserting a new line)
            document.querySelector('.btn[type="submit"]').click(); // Programmatically click the submit button
        }
    });
});