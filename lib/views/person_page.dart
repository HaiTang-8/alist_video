import 'package:flutter/material.dart';

class PersonPage extends StatefulWidget {
  const PersonPage({super.key});

  @override
  State<StatefulWidget> createState() => _PersonPageState();
}

class _PersonPageState extends State<PersonPage> {
  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Stack(
        children: [Text("PersonPage")],
      ),
    );
  }
}
