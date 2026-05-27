const puppeteer = require('puppeteer');
require('dotenv').config();
const { createClient } = require('@supabase/supabase-js');

// Configuración de Supabase
const supabaseUrl = process.env.SUPABASE_URL;
const supabaseKey = process.env.SUPABASE_ANON_KEY;
const supabase = (supabaseUrl && supabaseKey) ? createClient(supabaseUrl, supabaseKey) : null;

let cachedPoints = [];

const scrapeAbcData = async () => {
    console.log('[Scraper ABC] Iniciando proceso de recolección de puntos...');
    let browser;
    try {
        browser = await puppeteer.launch({
            headless: true,
            args: ['--no-sandbox', '--disable-setuid-sandbox']
        });

        const page = await browser.newPage();

        page.on('response', async (response) => {
            const url = response.url();
            
            if (url.includes('api') && (url.includes('transitabilidad') || url.includes('puntos') || url.includes('mapa'))) {
                try {
                    const data = await response.json();
                    if (data && (Array.isArray(data) || data.features)) {
                        console.log(`[Scraper ABC] ¡Datos interceptados exitosamente desde ${url}!`);
                        const puntos = data.features ? data.features : data;
                        cachedPoints = puntos;
                        
                        // Guardar en Supabase
                        if (supabase) {
                            console.log(`[Scraper ABC] Sincronizando ${puntos.length} puntos a Supabase...`);
                            // Asumiendo que guardamos cada punto completo en la columna original
                            // y usamos el id de la ABC para no duplicar
                            for (const p of puntos) {
                                const { error } = await supabase
                                    .from('puntos_abc')
                                    .upsert({
                                        id: p.id || p.properties?.id,
                                        datos_brutos: p // Guardamos todo el JSON por ahora
                                    });
                                if (error) console.error('[Scraper ABC] Error insertando punto:', error.message);
                            }
                            console.log('[Scraper ABC] Sincronización a Supabase completada.');
                        } else {
                            console.warn('[Scraper ABC] Advertencia: Credenciales de Supabase no configuradas (.env). Los puntos no se subirán.');
                        }
                    }
                } catch (e) {
                    // Ignorar errores de parseo
                }
            }
        });

        console.log('[Scraper ABC] Accediendo a transitabilidad.abc.gob.bo...');
        await page.goto('https://transitabilidad.abc.gob.bo/', {
            waitUntil: 'networkidle2',
            timeout: 60000 
        });

        console.log('[Scraper ABC] Búsqueda finalizada.');

    } catch (error) {
        console.error('[Scraper ABC] Error durante el scraping:', error.message);
    } finally {
        if (browser) {
            await browser.close();
        }
    }
};

const getCachedPoints = () => cachedPoints;

module.exports = {
    scrapeAbcData,
    getCachedPoints
};
