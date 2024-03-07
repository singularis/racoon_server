document.addEventListener('DOMContentLoaded', function() {
    const textarea = document.getElementById('question');
    textarea.addEventListener('input', function() {
        this.style.height = 'auto';
        this.style.height = (this.scrollHeight) + 'px';
    });
});
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