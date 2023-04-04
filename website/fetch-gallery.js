function fetchGallery(folderName) {
	// fetch the images from the directory
	fetch('https://api.github.com/repos/laurenz-glueck/charging-station-usage-history/contents/history-charts/' + folderName)
		.then(response => response.json())
		.then(images => {
			// filter the images based on the naming pattern
			const chartImages = images.filter(image => image.name.endsWith('.png')).sort((a, b) => b.name.localeCompare(a.name));

			// create chart cards for each image
			let chartGrid = '';
			for (let i = 0; i < chartImages.length; i++) {
				const image = chartImages[i];
				const imageSrc = image.download_url;
				const chartName = image.name.replace('.png', '');

				const chartCard = `
                    <div class="col">
                        <div class="card">
                            <img src="${imageSrc}" class="card-img-top" alt="${chartName}">
                            <div class="card-body">
                                <h5 class="card-title">${chartName}</h5>
                                <a href="${imageSrc}" class="btn btn-primary" target="_blank">View full size</a>
                            </div>
                        </div>
                    </div>
                `;

				chartGrid += chartCard;
			}

			// add chart cards to the chart grid
			document.getElementById('chart-grid').innerHTML = chartGrid;
		});
}
