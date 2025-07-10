import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:onboarding/homepage.dart';
import 'package:onboarding/onboardingScreen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = true;
  runApp(const MyApp());
}


class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ScreenUtilInit(
      designSize: Size(404, 812),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        home: OnBoardingPage(),
        initialRoute: OnBoardingPage.routeName,
        routes: {
          OnBoardingPage.routeName: (context) => const OnBoardingPage(),
          Homepage.routeName: (context) => const Homepage(),
        },
        
      ),
    );
  }
}
