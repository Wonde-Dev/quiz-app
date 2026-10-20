import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const headers = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Content-Type": "application/json",
};

function response(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers });
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers });
  if (request.method !== "POST") return response({ error: "Method not allowed" }, 405);

  const authorization = request.headers.get("Authorization");
  const url = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!authorization) return response({ error: "Authentication required" }, 401);
  if (!url || !anonKey || !serviceRoleKey) {
    return response({ error: "Function configuration is incomplete" }, 500);
  }

  const callerClient = createClient(url, anonKey, {
    global: { headers: { Authorization: authorization } },
  });
  const { data: authData, error: authError } = await callerClient.auth.getUser();
  if (authError || !authData.user) return response({ error: "Invalid session" }, 401);

  const serviceClient = createClient(url, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
  const { data: profile, error: profileError } = await serviceClient
    .from("users")
    .select("role, school_id")
    .eq("id", authData.user.id)
    .single();
  if (profileError || profile?.role !== "student") {
    return response({ error: "Only students can take quizzes" }, 403);
  }

  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return response({ error: "Request body must be valid JSON" }, 400);
  }
  if (!isRecord(body)) return response({ error: "Invalid request body" }, 400);
  if (typeof body.quizId !== "string" || !body.quizId) {
    return response({ error: "A quiz ID is required" }, 400);
  }

  const { data: quiz, error: quizError } = await serviceClient
    .from("quizzes")
    .select("id, teacher_id, course_id, section_id, title, description, time_limit_minutes, total_points, passing_score_percent")
    .eq("id", body.quizId)
    .eq("is_published", true)
    .maybeSingle();
  if (quizError) return response({ error: "Could not load this quiz" }, 500);
  if (!quiz) return response({ error: "Quiz is not available" }, 404);
  const { data: teacher, error: teacherError } = await serviceClient
    .from("users")
    .select("role, school_id")
    .eq("id", quiz.teacher_id)
    .single();
  if (teacherError || !teacher) {
    return response({ error: "Could not validate quiz access" }, 500);
  }
  if (
    teacher.role !== "admin" &&
    (!profile.school_id ||
      teacher.role !== "teacher" ||
      !teacher.school_id ||
      profile.school_id !== teacher.school_id)
  ) {
    return response({ error: "This quiz is not available to your school" }, 403);
  }
  if (quiz.section_id) {
    const { data: enrollment, error: enrollmentError } = await serviceClient
      .from("student_sections")
      .select("student_id")
      .eq("student_id", authData.user.id)
      .eq("section_id", quiz.section_id)
      .maybeSingle();
    if (enrollmentError) {
      return response({ error: "Could not verify your class enrollment" }, 500);
    }
    if (!enrollment) {
      return response({ error: "This quiz is for another grade or section" }, 403);
    }
  }

  const { data: questions, error: questionError } = await serviceClient
    .from("questions")
    .select("id, quiz_id, text, type, options, points, order, correct_answer, explanation")
    .eq("quiz_id", body.quizId)
    .order("order", { ascending: true });
  if (questionError) return response({ error: "Could not load quiz questions" }, 500);
  if (!questions?.length) return response({ error: "This quiz has no questions" }, 409);

  if (body.action === "start") {
    const { data: attempt, error: attemptError } = await serviceClient
      .from("grades")
      .select("id")
      .eq("student_id", authData.user.id)
      .eq("quiz_id", body.quizId)
      .maybeSingle();
    if (attemptError) return response({ error: "Could not check quiz attempts" }, 500);
    if (attempt) return response({ error: "You have already submitted this quiz" }, 409);

    return response({
      quiz,
      questions: questions.map((question) => ({
        ...question,
        correct_answer: null,
        explanation: null,
        options: Array.isArray(question.options)
          ? question.options.map((option: Record<string, unknown>) => ({
            id: option.id,
            text: option.text,
          }))
          : [],
      })),
    });
  }

  if (
    body.action !== "submit" ||
    !body.answers ||
    typeof body.answers !== "object" ||
    Array.isArray(body.answers)
  ) {
    return response({ error: "Unsupported action or invalid answers" }, 400);
  }

  const { data: priorAttempt, error: priorAttemptError } = await serviceClient
    .from("grades")
    .select("id")
    .eq("student_id", authData.user.id)
    .eq("quiz_id", body.quizId)
    .maybeSingle();
  if (priorAttemptError) return response({ error: "Could not check quiz attempts" }, 500);
  if (priorAttempt) return response({ error: "This quiz has already been submitted" }, 409);

  const answers = body.answers as Record<string, unknown>;
  let score = 0;
  let totalPoints = 0;
  let incorrectAnswers = 0;
  const feedback: Array<{
    question: string;
    explanation: string | null;
    isCorrect: boolean;
  }> = [];
  for (const question of questions) {
    const points = Number(question.points ?? 1);
    totalPoints += points;
    const answer = answers[question.id];
    let correct = false;
    if (question.type === "multiple_choice" || question.type === "true_false") {
      const options = Array.isArray(question.options) ? question.options : [];
      const correctOption = options.find(
        (option: Record<string, unknown>) => option.is_correct === true,
      );
      correct = correctOption != null && answer === correctOption.id;
    } else if (question.type === "short_answer" && question.correct_answer != null) {
      let textVal = "";
      if (typeof answer === "string") {
        try {
          const parsed = JSON.parse(answer);
          if (parsed && typeof parsed === "object" && "text" in parsed) {
            textVal = String(parsed.text ?? "");
          } else {
            textVal = answer;
          }
        } catch {
          textVal = answer;
        }
      } else if (answer && typeof answer === "object" && "text" in answer) {
        textVal = String((answer as Record<string, unknown>).text ?? "");
      } else {
        textVal = String(answer ?? "");
      }
      correct = textVal.trim().toLowerCase() ===
        String(question.correct_answer).trim().toLowerCase();
    }
    if (correct) {
      score += points;
    } else {
      incorrectAnswers += 1;
    }
    feedback.push({
      question: question.text,
      explanation: question.explanation,
      isCorrect: correct,
    });
  }

  const percentage = totalPoints > 0 ? Math.round((score / totalPoints) * 100) : 0;
  const { data: grade, error: gradeError } = await serviceClient
    .from("grades")
    .insert({
      student_id: authData.user.id,
      quiz_id: body.quizId,
      course_id: quiz.course_id,
      score,
      total_points: totalPoints,
      incorrect_answers: incorrectAnswers,
      percentage,
      passed: percentage >= Number(quiz.passing_score_percent ?? 60),
      submitted_at: new Date().toISOString(),
    })
    .select()
    .single();
  if (gradeError) return response({ error: "Could not save quiz result" }, 500);

  // Also record quiz attempt and individual answers for teacher evaluation
  try {
    const { data: attemptRecord } = await serviceClient
      .from("quiz_attempts")
      .upsert({
        quiz_id: body.quizId,
        student_id: authData.user.id,
        submitted_at: new Date().toISOString(),
        score,
      }, { onConflict: "quiz_id,student_id" })
      .select("id")
      .maybeSingle();

    const attemptId = attemptRecord?.id;
    if (attemptId) {
      const answersToInsert = questions.map((question) => {
        const rawAns = answers[question.id];
        const answerText = typeof rawAns === "object" && rawAns !== null
          ? JSON.stringify(rawAns)
          : String(rawAns ?? "");
        const isCorrect = feedback.find((f) => f.question === question.text)?.isCorrect ?? false;
        return {
          attempt_id: attemptId,
          question_id: question.id,
          answer_text: answerText,
          is_correct: isCorrect,
        };
      });
      await serviceClient.from("answers").insert(answersToInsert);
    }
  } catch (attemptErr) {
    console.error("Could not record attempt breakdown:", attemptErr);
  }

  return response({ grade, feedback });
});
