// Lambda handler for the fleet example.
//
// The greeting comes from the environment rather than a literal, so that
// patching the fleet (turf up with a different greeting) is observable by
// invoking a function — not just by reading the state file.

module.exports.handler = async (event) => {
  let message = process.env.GREETING || 'Hello, World!';

  const name = event?.queryStringParameters?.Name;
  if (name) {
    message = `${message} ${name}!`;
  }

  return {
    statusCode: 200,
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      message,
      function: process.env.AWS_LAMBDA_FUNCTION_NAME,
    }),
  };
};
