# Project History

This project was born from a very specific and very human need.

My mother was taking an extension course at a university, and the entire course lived inside a platform that was built around videos. There were no PDFs, no text handouts, and no alternate study material. Everything was in video form, and those videos were hosted on YouTube.

Her workflow was simple but repetitive: she would watch the lesson inside the platform, answer the questions, complete the assessments, and then open the corresponding YouTube link to copy the video URL into a TXT file. Over time, she built a neatly organized text file with each chapter and each YouTube link.

The problem was what came next.

Every time she needed to review something, she had to open the video again and watch it from scratch just to find a specific point or remember a detail. What she really wanted was the transcript of every video, so she could have the full course material in text form and use it whenever she needed to study.

But the course had almost 200 videos. Doing that manually, one by one, would take hours and would be exhausting.

So one afternoon she called me, which is how we usually solve problems together. Even though we live about 500 kilometers apart, we often jump on a video call to think through a problem side by side. She learns from me, I learn from her, and together we usually find a practical path forward.

When she explained the problem, she was thinking out loud: what if there were an app that could open each link, click the transcript button, copy the transcript, and save everything into one single file? In her mind, she imagined some kind of AI controlling the screen. And that was a fair assumption. To her, the important part was not how it worked internally, but that it could save time and turn a repetitive task into something manageable.

That idea became the starting point for this project.

What we learned along the way was important too. AI is excellent for research, discovery, and helping us get from zero to a useful prototype. But for repetitive work like this, it is much more reliable to turn the idea into deterministic code that behaves the same way every time. Otherwise, the process becomes slow, inconsistent, and fragile.

Another lesson was that speed matters.

Even with automation, processing almost 200 links one at a time would still feel slow. So the app evolved from a single WebView approach into a parallel batch process with multiple WebViews running at the same time. That change made the workflow much faster while keeping the output stable and ordered.

By the time the app was working, what had started as a practical request had become something more meaningful: a tool that turns a long, repetitive task into a reusable workflow, and a record of how we solve problems together.

This project is not just about extracting transcripts. It is also about collaboration, distance, learning, and the shared habit my mother and I have of turning a problem into something useful.
