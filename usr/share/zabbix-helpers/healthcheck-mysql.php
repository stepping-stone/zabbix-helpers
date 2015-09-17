<?php
/*
 * Copyright (C) 2015 stepping stone GmbH
 *                    Switzerland
 *                    http://www.stepping-stone.ch
 *                    support@stepping-stone.ch
 *  
 * Authors:
 *  Yannick Denzer <yannick.denzer@stepping-stone.ch>
 *  Pascal Jufer <pascal.jufer@stepping-stone.ch>
 *
 * This program is free software: you can redistribute it and/or
 * modify it under the terms of the GNU Affero General Public 
 * License as published  by the Free Software Foundation, version
 * 3 of the License.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Affero General Public License for more details.
 *
 * You should have received a copy of the GNU Affero General Public
 * License along with this program.
 * If not, see <http://www.gnu.org/licenses/>.
 *
 * Description:
 * Check the availability of a MySQL service by writing and reading
 * to resp. from a database. Return a corresponding HTTP code.
 *
 */

error_reporting(E_ALL);

class HealthCheckMysql {
	private $cfg, $hostname, $date;
	private $mysqli = null, $insert_id = -1;

	public function __construct($cfg) {
		$this->cfg = $cfg;
		$this->hostname = gethostname();
		$this->date = date('Y-m-d H:i:s');

		set_error_handler(array($this, 'error_handler'), E_ALL);

		if (openlog($this->cfg['syslog_ident'], $this->cfg['syslog_options'], $this->cfg['syslog_facility']) != true)
			$this->error('unable to open a connection to syslog');

		$this->mysqli = new mysqli($this->cfg['db_host'], $this->cfg['db_user'], $this->cfg['db_password'], $this->cfg['db_database'], $this->cfg['db_port']);

		if ($this->mysqli->connect_errno)
			$this->error('could not connect to database (%s): %s (%d)', $this->cfg['db_host'], $this->mysqli->connect_error, $this->mysqli->connect_errno);
	}

	public function run() {
		$id = $this->db_write();
		$this->db_read($id);

		$this->httpResponse(200);
		$this->cleanup();
		exit(0);
	}

	private function db_write() {
		$query = "INSERT INTO `{$this->cfg['db_table']}` (hostname, date) VALUES ('{$this->hostname}', '{$this->date}');";

		if (($result = $this->mysqli->query($query)) == FALSE)
			$this->error('Query failed: %s (%d)', $this->mysqli->error, $this->mysqli->errno);

		$this->insert_id = $this->mysqli->insert_id;
	}

	private function db_read() {
		$query = "SELECT hostname, date FROM `{$this->cfg['db_table']}` WHERE id = {$this->insert_id}";

		if (($result = $this->mysqli->query($query)) == false)
			$this->error('Query failed: %s (%d)', $this->mysqli->error, $this->mysqli->errno);

		$line = $result->fetch_assoc();

		if (!array_key_exists('hostname', $line) || !array_key_exists('date', $line))
			$this->error('Select query returned an invalid result (keys missing).');

		if ($line['hostname'] != $this->hostname)
			$this->error('Hostname: expected "%s", got "%s".', $this->hostname, $line['hostname']);

		if ($line['date'] != $this->date)
			$this->error('Date: expected "%s", got "%s".', $this->hostname, $line['host']);

		$result->close();
	}

	private function cleanup() {
		// Ignore any errors during cleanup.

		if ($this->mysqli) {
			if ($this->insert_id >= 0)
				$this->mysqli->query("DELETE FROM `{$this->cfg['db_table']}` WHERE id = {$this->insert_id}");

			$this->mysqli->close();
		}

		closelog();
	}

	private function error_handler($errno, $errstr, $errfile, $errline, $errctx) {
		$this->error('PHP error %d on line %d in file %s: %s', $errno, $errline, $errfile, $errstr);
	}

	private function error() {
		$args = func_get_args();
		$msg = vsprintf($args[0], array_slice($args, 1));

		syslog(LOG_ERR, $msg);
		$this->httpResponse(500, $msg);
		$this->cleanup();
		exit(0);
	}

	private function httpResponse($code = 200, $msg = null) {
		$responses = array
			( 200 => 'OK'
			, 500 => 'Internal Server Error'
			);

		$response = array_key_exists($code, $responses) ? $responses[$code] : 'Unknown';

		header("HTTP/1.0 $code $response\r\n");
		header("Content-type: text/html; charset=utf-8\r\n");
		header("Conection: close\r\n\r\n");

		printf	( '<html><head><title>%1$d %2$s</title></head><body><h1>%1$d %2$s</h1>%3$s</body></html>' . "\n"
			, $code
			, $response
			, $msg != null ? "<p>$msg</p>" : ''
			);
	}
}

require_once(dirname(__FILE__) . '/../../../etc/zabbix-helpers/healthcheck-mysql.conf');

$hc = new HealthCheckMysql($_CONFIG);
$hc->run();
?>
