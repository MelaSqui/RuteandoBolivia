import 'package:flutter/material.dart';
import 'package:ruteando_bolivia/features/map/presentation/screens/map_screen.dart';
import 'package:ruteando_bolivia/features/alerts/presentation/screens/alerts_screen.dart';
import 'package:ruteando_bolivia/features/reports/presentation/screens/reports_screen.dart';
import 'package:ruteando_bolivia/features/profile/presentation/screens/profile_screen.dart';
import 'package:ruteando_bolivia/features/discovery/presentation/screens/discovery_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    final screens = [
      DiscoveryScreen(
        onNavigateToMap: () {
          setState(() {
            _currentIndex = 3; // Redirige a la pestaña de la Red Vial / Rutas (donde ahora está el Mapa)
          });
        },
      ),
      const AlertsScreen(),
      const ReportsScreen(),
      const MapaTransitabilidad(), // El mapa real interactivo ahora está en la pestaña "Rutas"
      const ProfileScreen(),
    ];

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: screens,
      ),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed, // Asegura que se muestren las 5 opciones fijas
        currentIndex: _currentIndex,
        selectedItemColor: Theme.of(context).colorScheme.primary,
        unselectedItemColor: Colors.grey,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.map_rounded),
            label: 'Mapa',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.warning_amber_rounded),
            label: 'Alertas',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.add_circle_outline_rounded),
            label: 'Reportar',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.directions_rounded),
            label: 'Rutas',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_rounded),
            label: 'Perfil',
          ),
        ],
      ),
    );
  }
}
