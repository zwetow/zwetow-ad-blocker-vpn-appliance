#!/usr/bin/env node
const fs = require("fs");

async function main() {
    const chunks = [];
    for await (const chunk of process.stdin) {
        chunks.push(chunk);
    }

    let payload;
    try {
        payload = JSON.parse(Buffer.concat(chunks).toString("utf8") || "{}");
    } catch (error) {
        return fail(`Invalid JSON input: ${error.message}`, 2);
    }

    const username = String(payload.username || "").trim();
    const password = String(payload.password || "");
    if (!username || !password) {
        return fail("username and password are required", 2);
    }

    const kumaRoot = process.env.ZWETOW_KUMA_ROOT || "/opt/uptime-kuma";
    if (!fs.existsSync(kumaRoot)) {
        return fail(`Uptime Kuma root not found at ${kumaRoot}`, 4);
    }

    process.chdir(kumaRoot);

    const Database = require("/opt/uptime-kuma/server/database");
    const { R } = require("redbean-node");
    const passwordHash = require("/opt/uptime-kuma/server/password-hash");
    const { initJWTSecret } = require("/opt/uptime-kuma/server/util-server");

    try {
        Database.initDataDir({
            "data-dir": process.env.ZWETOW_KUMA_DATA_DIR || undefined,
        });
        await Database.connect(false, false, true);

        const countRow = await R.knex("user").count("id as count").first();
        const userCount = Number(countRow.count || 0);
        const hashedPassword = await passwordHash.generate(password);

        let message;

        if (userCount === 0) {
            const user = R.dispense("user");
            user.username = username;
            user.password = hashedPassword;
            user.active = 1;
            await R.store(user);
            message = `created first Uptime Kuma admin '${username}'`;
        } else {
            let user = await R.findOne("user", " username = ? ", [username]);
            if (user) {
                await R.exec("UPDATE `user` SET password = ?, active = 1 WHERE id = ?", [
                    hashedPassword,
                    user.id,
                ]);
                message = `updated password for existing Uptime Kuma admin '${username}'`;
            } else {
                user = await R.findOne("user");
                if (!user) {
                    return fail("Could not load an existing Uptime Kuma user", 5);
                }
                await R.exec("UPDATE `user` SET username = ?, password = ?, active = 1 WHERE id = ?", [
                    username,
                    hashedPassword,
                    user.id,
                ]);
                message = `updated native Uptime Kuma admin to '${username}'`;
            }
        }

        await initJWTSecret();
        await Database.close();
        process.stdout.write(JSON.stringify({
            ok: true,
            message,
        }));
    } catch (error) {
        try {
            await Database.close();
        } catch (_) {
        }
        return fail(error.message, 5);
    }
}

function fail(message, code) {
    process.stdout.write(JSON.stringify({
        ok: false,
        error: message,
    }));
    process.exit(code);
}

main();
