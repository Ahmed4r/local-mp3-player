import 'package:flutter/material.dart';

class Homepage extends StatelessWidget {
  static const String routeName = '/homepage';
  const Homepage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(onPressed: (){
          Navigator.pop(context);
        }, icon: Icon(Icons.arrow_back_ios_new)),
      ),
    );
  }
}