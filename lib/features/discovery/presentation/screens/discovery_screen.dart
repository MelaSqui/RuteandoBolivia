import 'package:flutter/material.dart';
import 'dart:ui';
import '../../data/repositories/discovery_repository.dart';
import '../../domain/entities/tourist_destination.dart';

class DiscoveryScreen extends StatefulWidget {
  final VoidCallback onNavigateToMap;

  const DiscoveryScreen({
    super.key,
    required this.onNavigateToMap,
  });

  @override
  State<DiscoveryScreen> createState() => _DiscoveryScreenState();
}

class _DiscoveryScreenState extends State<DiscoveryScreen> {
  final DiscoveryRepository _repository = DiscoveryRepository();
  List<TouristDestination> _destinations = [];
  List<String> _blockedRoutes = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final futures = await Future.wait([
        _repository.getTouristDestinations(),
        _repository.getActiveBlockades(),
      ]);
      
      if (!mounted) return;
      setState(() {
        _destinations = futures[0] as List<TouristDestination>;
        _blockedRoutes = futures[1] as List<String>;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  bool _isDestinationBlocked(TouristDestination destination) {
    return destination.requiredHighways.any((route) => _blockedRoutes.contains(route));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.colorScheme.background,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _fetchData,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Descubrir Bolivia',
                        style: theme.textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Explora destinos turísticos seguros para tu próximo viaje.',
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: theme.textTheme.bodySmall?.color,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (_isLoading)
                const SliverFillRemaining(
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_destinations.isEmpty)
                SliverFillRemaining(
                  child: Center(
                    child: Text('No se encontraron destinos.'),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  sliver: SliverToBoxAdapter(
                    child: SizedBox(
                      height: 480, // Alto incrementado para dar espacio a los botones del card
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: _destinations.length,
                        itemBuilder: (context, index) {
                          final destination = _destinations[index];
                          final isBlocked = _isDestinationBlocked(destination);
                          
                          return Padding(
                            padding: const EdgeInsets.only(right: 16),
                            child: _DestinationCard(
                              destination: destination,
                              isBlocked: isBlocked,
                              isDark: isDark,
                              onNavigateToMap: widget.onNavigateToMap,
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DestinationCard extends StatelessWidget {
  final TouristDestination destination;
  final bool isBlocked;
  final bool isDark;
  final VoidCallback onNavigateToMap;

  const _DestinationCard({
    required this.destination,
    required this.isBlocked,
    required this.isDark,
    required this.onNavigateToMap,
  });

  void _openAiChatSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _AiChatBottomSheet(
        destination: destination,
        isBlocked: isBlocked,
        isDark: isDark,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Container(
      width: 300,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        color: isDark ? const Color(0xFF1E2329) : Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.3 : 0.05),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Image Background
            if (destination.imageUrl != null && destination.imageUrl!.isNotEmpty)
              Image.network(
                destination.imageUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _buildPlaceholder(theme),
              )
            else
              _buildPlaceholder(theme),

            // Gradient Overlay for text readability
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withOpacity(0.9),
                  ],
                  stops: const [0.3, 0.95],
                ),
              ),
            ),

            // Content
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.location_on, size: 16, color: Colors.white.withOpacity(0.9)),
                      const SizedBox(width: 4),
                      Text(
                        destination.department,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: Colors.white.withOpacity(0.9),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    destination.name,
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    destination.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.white.withOpacity(0.8),
                    ),
                  ),
                  const SizedBox(height: 18),
                  
                  // Botones Side-by-Side (Interactuar con IA y Ver Mapa)
                  Row(
                    children: [
                      // Botón Consultar IA
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: Colors.white.withOpacity(0.15),
                                ),
                              ),
                              child: TextButton.icon(
                                onPressed: () => _openAiChatSheet(context),
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                  foregroundColor: Colors.white,
                                ),
                                icon: const Icon(Icons.assistant_rounded, size: 16, color: Colors.cyanAccent),
                                label: const Text(
                                  'Preguntar IA',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      
                      // Botón Ver Mapa
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: onNavigateToMap,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: theme.colorScheme.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          icon: const Icon(Icons.map_rounded, size: 16),
                          label: const Text(
                            'Ver Mapa',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Blocked Warning Badge
            if (isBlocked)
              Positioned(
                top: 16,
                right: 16,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withOpacity(0.95),
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.redAccent.withOpacity(0.4),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.warning_rounded, color: Colors.white, size: 16),
                      const SizedBox(width: 6),
                      Text(
                        'Ruta Bloqueada',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaceholder(ThemeData theme) {
    return Container(
      color: theme.colorScheme.primaryContainer,
      child: Center(
        child: Icon(
          Icons.landscape_rounded,
          size: 64,
          color: theme.colorScheme.primary.withOpacity(0.5),
        ),
      ),
    );
  }
}

/// Panel interactivo de Chat con Inteligencia Artificial (Ruteando AI)
class _AiChatBottomSheet extends StatefulWidget {
  final TouristDestination destination;
  final bool isBlocked;
  final bool isDark;

  const _AiChatBottomSheet({
    required this.destination,
    required this.isBlocked,
    required this.isDark,
  });

  @override
  State<_AiChatBottomSheet> createState() => _AiChatBottomSheetState();
}

class _AiChatBottomSheetState extends State<_AiChatBottomSheet> {
  final List<Map<String, String>> _messages = [];
  bool _isTyping = false;

  @override
  void initState() {
    super.initState();
    // Mensaje de bienvenida
    _messages.add({
      'role': 'ai',
      'text': '¡Hola viajero! Soy Ruteando AI. Pregúntame lo que quieras sobre la ruta o estado del viaje hacia ${widget.destination.name}.'
    });
  }

  void _sendMessage(String text) {
    setState(() {
      _messages.add({'role': 'user', 'text': text});
      _isTyping = true;
    });

    // Simulamos respuesta detallada de la IA en tiempo real basada en el estado real del destino
    Future.delayed(const Duration(milliseconds: 1200), () {
      if (!mounted) return;
      
      String aiResponse = "";
      if (text.contains('camino') || text.contains('estado') || text.contains('seguro')) {
        if (widget.isBlocked) {
          aiResponse = '⚠️ Actualmente, la ruta hacia ${widget.destination.name} se encuentra COMPROMETIDA por un bloqueo. Las carreteras de acceso: (${widget.destination.requiredHighways.join(', ')}) reportan tramos intransitables por conflictos sociales o derrumbes. Te sugiero ver las alternativas en la sección "Alertas" antes de partir.';
        } else {
          aiResponse = '✅ ¡Buenas noticias! El trayecto hacia ${widget.destination.name} está COMPLETAMENTE TRANSITABLE. Las carreteras de acceso: (${widget.destination.requiredHighways.join(', ')}) se reportan limpias y fluidas. Puedes viajar con tranquilidad.';
        }
      } else if (text.contains('clima') || text.contains('tiempo')) {
        aiResponse = '🌤️ El reporte climatológico para la ruta hacia ${widget.destination.name} indica cielo mayormente despejado con temperaturas templadas. Perfecto para manejar de día, pero ten precaución en los descensos nocturnos.';
      } else if (text.contains('alternativa') || text.contains('desvío')) {
        if (widget.isBlocked) {
          aiResponse = '🔄 Al tener la ruta principal bloqueada, hay conductores que intentan desvíos comunales no oficiales. Sin embargo, no te sugiero tomarlos ya que no están resguardados. Es preferible que uses el mapa interactivo para ver si existe una Red Vial Fundamental alterna despejada.';
        } else {
          aiResponse = '🛣️ Dado que las carreteras de la Red Vial Fundamental hacia ${widget.destination.name} están despejadas, no necesitas desvíos temporales. El camino principal es el más rápido y seguro en este momento.';
        }
      } else {
        aiResponse = '¡Qué buen destino! ${widget.destination.name} es espectacular. Recuerda siempre verificar nuestro mapa interactivo de transitabilidad antes de encender el motor y reportar cualquier eventualidad en el camino para ayudar a otros viajeros.';
      }

      setState(() {
        _messages.add({'role': 'ai', 'text': aiResponse});
        _isTyping = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    // Sugerencias de preguntas predefinidas
    final suggestions = [
      '¿Cómo está el camino hoy?',
      '¿Qué clima se reporta?',
      '¿Hay rutas alternativas?',
    ];

    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF161A20) : Colors.white,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(28),
          topRight: Radius.circular(28),
        ),
      ),
      child: Column(
        children: [
          // Drag Handle
          const SizedBox(height: 12),
          Container(
            width: 48,
            height: 5,
            decoration: BoxDecoration(
              color: Colors.grey.withOpacity(0.4),
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          
          // Header
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: theme.colorScheme.primary.withOpacity(0.1),
                  child: Icon(Icons.assistant_rounded, color: theme.colorScheme.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Ruteando AI',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Consultando viaje a ${widget.destination.name}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.textTheme.bodySmall?.color,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          
          // Chat Messages
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(20),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final message = _messages[index];
                final isAi = message['role'] == 'ai';
                
                return Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Row(
                    mainAxisAlignment: isAi ? MainAxisAlignment.start : MainAxisAlignment.end,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (isAi) ...[
                        CircleAvatar(
                          radius: 14,
                          backgroundColor: Colors.cyan.withOpacity(0.15),
                          child: const Icon(Icons.assistant_rounded, size: 14, color: Colors.cyan),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Flexible(
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: isAi 
                                ? (isDark ? Colors.white.withOpacity(0.05) : Colors.grey.withOpacity(0.1))
                                : theme.colorScheme.primary,
                            borderRadius: BorderRadius.only(
                              topLeft: const Radius.circular(16),
                              topRight: const Radius.circular(16),
                              bottomLeft: Radius.circular(isAi ? 4 : 16),
                              bottomRight: Radius.circular(isAi ? 16 : 4),
                            ),
                          ),
                          child: Text(
                            message['text'] ?? '',
                            style: TextStyle(
                              color: isAi 
                                  ? (isDark ? Colors.white : Colors.black87)
                                  : Colors.white,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          
          // Indicador de "Escribiendo..."
          if (_isTyping)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                children: [
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.cyan),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Ruteando AI está analizando las carreteras...',
                    style: theme.textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic),
                  ),
                ],
              ),
            ),
            
          // Sugerencias de Preguntas
          if (!_isTyping)
            SizedBox(
              height: 48,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: suggestions.length,
                itemBuilder: (context, index) {
                  final suggestion = suggestions[index];
                  return Padding(
                    padding: const EdgeInsets.only(right: 8, bottom: 8),
                    child: ActionChip(
                      onPressed: () => _sendMessage(suggestion),
                      backgroundColor: isDark ? const Color(0xFF1E2329) : Colors.grey.withOpacity(0.08),
                      side: BorderSide.none,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      label: Text(
                        suggestion,
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.white70 : Colors.black87,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}
