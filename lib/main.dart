import 'package:audioplayer/screens/audioplayer_screen.dart';
import 'package:audioplayer/screens/homepage.dart';
import 'package:audioplayer/screens/onboardingScreen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:shared_preferences/shared_preferences.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = true;
   final prefs = await SharedPreferences.getInstance();
  final seenOnboarding = prefs.getBool('onboarding_done') ?? false;
   runApp(MyApp(seenOnboarding: seenOnboarding));
}

class MyApp extends StatelessWidget {
  final bool seenOnboarding;
   const MyApp({super.key,required this.seenOnboarding});

  @override
  Widget build(BuildContext context) {
    return ScreenUtilInit(
      designSize: Size(404, 812),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        home: OnBoardingPage(),
      initialRoute: seenOnboarding ? Homepage.routeName : OnBoardingPage.routeName,
        routes: {
          OnBoardingPage.routeName: (context) => const OnBoardingPage(),
          Homepage.routeName: (context) => const Homepage(),
          AudioplayerScreen.routeName : (context) => const AudioplayerScreen(),
        },
        
      ),
    );
  }
}
