// open_sesame — variables & secrets, demonstrated in ~40 lines.
//
// The values arrive as environment bindings, same names as declared in
// qube.json5 `imports`:
//
//   env.GREETING         — a project VARIABLE  (console → Variables & Secrets)
//   env.SESAME_PASSWORD  — a project SECRET    (write-only, encrypted at rest)
//
// Nothing here fetches, decrypts, or configures anything: by the time this
// handler runs, the platform has already validated (at deploy) that both values
// exist and injected them. A plain Workers-style handler reads them off `env`.

const json = (status, body) =>
	new Response(JSON.stringify(body, null, 2) + '\n', {
		status,
		headers: { 'content-type': 'application/json; charset=utf-8' }
	});

export default {
	async fetch(request, env) {
		const url = new URL(request.url);

		// GET /open?password=…  — the door. Only the project secret opens it.
		if (url.pathname === '/open' || url.pathname.endsWith('/open')) {
			const guess = url.searchParams.get('password') ?? '';
			if (guess === env.SESAME_PASSWORD) {
				return json(200, {
					door: 'open',
					message: `${env.GREETING ?? 'Welcome'}! The mountain parts before you.`,
					treasure: ['a lamp (slightly used)', '40 abandoned login sessions', 'one (1) wish']
				});
			}
			return json(403, {
				door: 'sealed',
				message: 'The mountain does not know these words.',
				hint: 'GET /open?password=<the project secret SESAME_PASSWORD>'
			});
		}

		// GET / — prove the variable arrived, and prove the secret did NOT leak:
		// we only ever reveal that it exists, never its value.
		return json(200, {
			qube: 'qubepods.examples.open_sesame',
			greeting: env.GREETING ?? '(variable GREETING not set)',
			secretConfigured: typeof env.SESAME_PASSWORD === 'string' && env.SESAME_PASSWORD.length > 0,
			try: 'GET /open?password=…'
		});
	}
};
