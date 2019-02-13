---
title: Getting started
layout: document
parent: ['Guides', '../../guides.html']
toc: true
---

# What is Radix?

Omnia Radix is a Platform-as-a-Service ("PaaS", if you like buzzwords). It builds, deploys, and monitors applications, automating the boring stuff and letting developers focus on code. Applications run in <abbr title="someone else's computer">the cloud</abbr> as Docker containers, in environments that you define.

You can use Radix just to run code, but the main functionality is to integrate with a code repository so that it can continuously build, test, and deploy applications. For instance, Radix can react to a `git push` event, automatically start a new build, and push it to the `test` environment, ready to be tested by users.

Radix also provides monitoring for applications. There are default metrics (e.g. request latency, failure rate), but you can also output custom metrics from your code. Track things that are important for your application: uploaded file size, number of results found, or user preferences. Radix collects and monitors the data.

# Requirements

There aren't many requirements: Radix runs applications written in Python, Java, .NET, JavaScript, or [LOLCODE](https://en.wikipedia.org/wiki/LOLCODE) equally well. If it can be built and deployed as Docker containers, we are nearly ready. If not, it's not hard to "dockerise" most applications.

An in-depth understanding of Docker is not a requirement, but it helps to be familiar with the concepts of containers and images. There are many beginner tutorials online; here's one of the most straightforward: [Getting Started with Docker](https://scotch.io/tutorials/getting-started-with-docker).

It is also expected that you have a [basic understanding of Git](http://rogerdudler.github.io/git-guide/) (branching, merging) and some networking (ports, domain names).

## Getting access

You need to be part of the `fg_radix_platform_user` AD group to create and adminsiter your applications in Radix. For now, the easiest way to be added to this group is to post a request on [the `#omnia_radix_support` channel](https://equinor.slack.com/messages/CBKM6N2JY) Slack channel.

> To help improve Radix, request access to the GitHub [Omnia Radix Readers](https://github.com/orgs/equinor/teams/omnia-radix-readers/members) team — this gives you access to poke around in our repositories. We track **issues and feature requests** in the [radix-platform](https://github.com/equinor/radix-platform/issues) repo. Please log those! 🙂

# Onwards

Let's jump right in and see how to [configure an application](../configure-an-app) in Radix.

Or, if you prefer reading rather than coding right now, you can read about the [concepts in Radix](docs/topic-concepts) instead.