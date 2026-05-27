const express = require('express');
const cors = require('cors');
const cron = require('node-cron');
const abcScraper = require('./scraper');

const app = express();
const PORT = process.env.PORT || 8081; 

app.use(cors());
app.use(express.json());

// Ruta limpia para devolver los puntos a tu App Flutter
app.get('/api/transitabilidad/puntos', (req, res) => {
    const data = abcScraper.getCachedPoints();
    res.json({
        success: true,
        timestamp: new Date().toISOString(),
        total_puntos: data.length || 0,
        data: data
    });
});

app.get('/healthz', (req, res) => {
    res.status(200).send('Microservicio Scraper OK');
});

app.listen(PORT, () => {
    console.log(`[Scraper API] Servidor escuchando en el puerto :${PORT}`);
    
    // Ejecutar el scraper por primera vez
    abcScraper.scrapeAbcData();

    // Configurar cron job para ejecutar cada 30 minutos
    // (Un tiempo más prudente, ya que los bloqueos no cambian minuto a minuto)
    cron.schedule('*/30 * * * *', () => {
        console.log('[Scraper API] Ejecutando tarea programada (cada 30 mins)...');
        abcScraper.scrapeAbcData();
    });
});
