import 'package:cms/widgets/gradient_header.dart';
import 'package:flutter/material.dart';
import 'character_select_page.dart';

class NamePage extends StatefulWidget {
  const NamePage({super.key});

  @override
  State<NamePage> createState() => _NamePageState();
}

class _NamePageState extends State<NamePage> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF5522A3),

      body: SafeArea(
        child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Center(
          
          child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            GradientHeader(text: 'Christmas', fontSize: 45,),
            GradientHeader(text: 'Coloring', fontSize: 45,),
               const Center(
              child: Text(
                'Create your festive masterpiece',
                style: TextStyle(color: Colors.white70),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              style: TextStyle(color: Colors.white),
              controller: _controller,
              decoration: const InputDecoration(
                labelText: 'What is your name?',
                border: OutlineInputBorder(),
                labelStyle: TextStyle(color: Colors.white, fontSize: 16),
                
              ),
            ),
            const SizedBox(height: 16),
            GestureDetector(
              onTap:  () {
                final name = _controller.text.trim();
                if (name.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please enter your name')),
                  );
                  return;
                }
                Navigator.of(context).pushNamed(
                  CharacterSelectPage.routeName,
                  arguments: name,
                );
              },
              child:         Container(
              padding: const EdgeInsets.all(25),
              decoration: BoxDecoration(
                color: const Color.fromARGB(255, 110, 20, 246),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Center(
                child: Text('Start Creating →', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
              ),
            ) ,
            ),
   

          ],
        ),
      ),
    )));
  }
}


