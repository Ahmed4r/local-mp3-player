import 'package:audioplayer/screens/homepage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:introduction_screen/introduction_screen.dart';

import 'package:shared_preferences/shared_preferences.dart';

class OnBoardingPage extends StatefulWidget {
  static const String routeName = '/OnBoardingPage';
  const OnBoardingPage({super.key});

  @override
  OnBoardingPageState createState() => OnBoardingPageState();
}

class OnBoardingPageState extends State<OnBoardingPage> {
  final introKey = GlobalKey<IntroductionScreenState>();
  late final PageController _pageController;
  TextEditingController? controller = TextEditingController();

  Future<void> _completeOnboarding(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_done', true);
    Navigator.of(context).pushReplacementNamed(Homepage.routeName);
   
  }

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _onIntroEnd(context) {
    _completeOnboarding(context);
    Navigator.of(context).pushReplacementNamed(Homepage.routeName);
  }

  Widget _buildImage(String assetName, [double width = 350]) {
    return Image.asset('assets/$assetName', width: width, cacheWidth: 300,filterQuality: FilterQuality.high,fit: BoxFit.cover,);
  }

  @override
  Widget build(BuildContext context) {
    const bodyStyle = TextStyle(fontSize: 19.0, color: Colors.white);

    const pageDecoration = PageDecoration(
      titleTextStyle: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: Colors.white),
      bodyTextStyle: bodyStyle,
      bodyPadding: EdgeInsets.fromLTRB(16.0, 0.0, 16.0, 16.0),
      pageColor: Colors.black,
      imagePadding: EdgeInsets.zero,
    );

    return IntroductionScreen(
      resizeToAvoidBottomInset: true,
      key: introKey,
      globalBackgroundColor: Colors.black,
      allowImplicitScrolling: true,
      pages: [
        PageViewModel(
          title: "Hi there!",
          body: "Get started with our app and explore all the features designed to help you succeed.",
          image: _buildImage('Charco Hi.png'),
          decoration: pageDecoration,
        ),
        PageViewModel(
          image: SingleChildScrollView(
            child: Column(
              children: [
                SizedBox(height: 170.h),
                Text(
                  "Who are you ?",
                  style: TextStyle(fontSize: 28.0.sp, fontWeight: FontWeight.w700, color: Colors.white),
                ),
                SizedBox(height: 40.h),
                Text(
                  "Please enter your name below",
                  style: TextStyle(fontSize: 16.0.sp, fontWeight: FontWeight.normal, color: Colors.white),
                ),
              ],
            ),
          ),
          title: "lallalalalal",
          bodyWidget: SingleChildScrollView(
            child: Column(
              children: [
                Container(
                  width: 343.w,
                  height: 62.h,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(25),
                  ),
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'Your name',
                      hintStyle: TextStyle(color: Colors.white70),
                      filled: true,
                      fillColor: Colors.grey[900],
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    style: TextStyle(color: Colors.white),
                    controller: controller,
                  ),
                ),
              ],
            ),
          ),
          decoration: pageDecoration.copyWith(
            titleTextStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal, color: Colors.transparent),
          ),
        ),
        PageViewModel(
          title: "Hello ${controller!.text.isNotEmpty ? controller!.text.toString() : "User"}",
          body: "Welcome to the app! We're glad to have you here.",
          image: _buildImage('Charco Good Job.png'),
          decoration: pageDecoration.copyWith(
            bodyFlex: 6,
            imageFlex: 6,
            safeArea: 80,
          ),
          footer: Center(
            child: InkWell(
              onTap: () {
                _completeOnboarding(context);
              },
              child: Container(
                height: 54.h,
                width: 140.w,
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(30.r),
                  border: Border.all(color: Colors.white),
                ),
                child: Center(
                  child: Text(
                    "Let's go!",
                    style: TextStyle(color: Colors.white, fontSize: 20.sp, fontWeight: FontWeight.w500),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
      onChange: (value) => setState(() {}),
      onDone: () => _onIntroEnd(context),
      onSkip: () => _onIntroEnd(context),
      showSkipButton: true,
      skipOrBackFlex: 0,
      nextFlex: 0,
      showBackButton: false,
      back: const Icon(Icons.arrow_back, color: Colors.white),
      skip: const Text('Skip', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.white)),
      next: const Icon(Icons.arrow_forward, color: Colors.white),
      done: const Text('Done', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.white)),
      curve: Curves.fastLinearToSlowEaseIn,
      controlsMargin: const EdgeInsets.all(16),
      controlsPadding: kIsWeb
          ? const EdgeInsets.all(12.0)
          : const EdgeInsets.fromLTRB(8.0, 4.0, 8.0, 4.0),
      dotsDecorator: const DotsDecorator(
        activeColor: Colors.white,
        size: Size(10.0, 10.0),
        color: Color(0xFF616161),
        activeSize: Size(22.0, 10.0),
        activeShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(40)),
        ),
      ),
      dotsContainerDecorator: const ShapeDecoration(
        color: Colors.black,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(8.0)),
        ),
      ),
    );
  }
}
