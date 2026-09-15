document.addEventListener('DOMContentLoaded', function () {
    // FAQ Toggle
    const qaItems = document.querySelectorAll('.qa');

    qaItems.forEach(item => {
        item.addEventListener('click', function () {
            const isActive = this.classList.contains('active');

            qaItems.forEach(otherItem => {
                otherItem.classList.remove('active');
            });

            if (!isActive) {
                this.classList.add('active');
            }
        });
    });

});