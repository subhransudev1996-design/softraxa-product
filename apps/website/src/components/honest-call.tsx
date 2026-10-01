"use client";

import Link from "next/link";
import Image from "next/image";
import { ArrowRight } from "lucide-react";
import Reveal from "./reveal";


export default function HonestCall() {
  return (
    <section className="relative overflow-hidden py-20 bg-[#FDF6EC]">
      <div className="relative mx-auto max-w-2xl px-6 text-center">
        <Reveal>
          {/* waving-hand sparkle accent — top-left of the avatar grid */}
          <div className="relative mx-auto w-fit mb-10">
            {/* sparkle / wave icon top-left */}
            <svg
              className="absolute -left-8 -top-4 h-6 w-6 text-[#1A1A1A] select-none"
              viewBox="0 0 24 24"
              fill="none"
              stroke="currentColor"
              strokeWidth="2.5"
              strokeLinecap="round"
              strokeLinejoin="round"
              aria-hidden="true"
            >
              <path d="M6 12L2 8" />
              <path d="M6 6L4 2" />
              <path d="M12 6L8 2" />
            </svg>

            {/* The Dukania app icon (not stock photos of people who aren't us). */}
            <Image
              src="/images/dukania/icon.png"
              width={112}
              height={112}
              alt="Dukania"
              className="h-28 w-28 rounded-[28px] shadow-xl"
              priority
            />

            {/* curved yellow/amber arrow */}
            <svg
              className="absolute -right-12 top-[40%] h-12 w-12 text-amber-500 transform -rotate-12 select-none"
              viewBox="0 0 48 48"
              fill="none"
              xmlns="http://www.w3.org/2000/svg"
              aria-hidden="true"
            >
              <path
                d="M6 36C18 36 32 30 38 18"
                stroke="currentColor"
                strokeWidth="5"
                strokeLinecap="round"
              />
              <path
                d="M26 14L40 16L36 30"
                stroke="currentColor"
                strokeWidth="5"
                strokeLinecap="round"
                strokeLinejoin="round"
              />
            </svg>

            {/* 4-point sparkle star */}
            <svg
              className="absolute -right-2 bottom-6 h-5 w-5 text-[#1A1A1A] select-none"
              viewBox="0 0 24 24"
              fill="currentColor"
              aria-hidden="true"
            >
              <path d="M12 0L14.6 9.4L24 12L14.6 14.6L12 24L9.4 14.6L0 12L9.4 9.4L12 0Z" />
            </svg>
          </div>

          {/* Heading — dark text on cream bg */}
          <h2 className="font-display text-4xl font-extrabold tracking-tight text-[#1A1A1A] sm:text-5xl">
            Will Dukania work for you?
          </h2>

          {/* Subtext */}
          <p className="mt-5 text-base text-[#555]">
            Get an honest answer from our team without a pitch.
            <br />
            Looking for technical support instead?{" "}
            <Link href="/dukania#faq" className="font-semibold text-[#1A1A1A] underline underline-offset-4 hover:text-amber-600">
              Visit our FAQ
            </Link>
            .
          </p>

          {/* Button — warm amber/gold pill matching the reference */}
          <div className="mt-8 flex justify-center">
            <Link
              href="/contact"
              className="inline-flex min-h-11 items-center gap-2 rounded-lg bg-[#F5D680] px-6 py-3 text-sm font-bold text-[#1A1A1A] shadow-sm hover:bg-[#f0cc60] transition-colors"
            >
              Book a meeting <ArrowRight className="h-4 w-4" />
            </Link>
          </div>
        </Reveal>
      </div>
    </section>
  );
}
