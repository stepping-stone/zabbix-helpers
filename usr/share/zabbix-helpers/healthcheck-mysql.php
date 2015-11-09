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

class HealthCheckMysql {
	private $cfg, $hostname, $date, $src_ip_addr, $app_name;
	private $disable_shutdown_function = false, $mysqli = null, $insert_id = -1;

	public function __construct($cfg) {
		$this->cfg		= $cfg;
		$this->hostname		= gethostname();
		$this->date		= date('Y-m-d H:i:s');
		$this->src_ip_addr	= array_key_exists('REMOTE_ADDR', $_SERVER) ? $_SERVER['REMOTE_ADDR'] : '0.0.0.0';
		$this->app_name		= array_key_exists('app', $_GET) ? $_GET['app'] : 'default';

		set_error_handler(array($this, 'error_handler'), E_ALL);
		register_shutdown_function(array($this, 'error_handler'));

		if (openlog($this->cfg['syslog_ident'], $this->cfg['syslog_options'], $this->cfg['syslog_facility']) != true)
			$this->error('unable to open a connection to syslog');

		if (!preg_match('/^([0-9]+\.){3}[0-9]+$/', $this->src_ip_addr) || strlen($this->src_ip_addr) > 45)
			$this->error('Source IP address contains invalid characters or is too long.');

		if (!preg_match('/^[a-zA-Z0-9._-]+$/', $this->app_name) || strlen($this->app_name) > 32)
			$this->error('Application name contains invalid characters or is too long.');

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
		$query = "INSERT INTO `{$this->cfg['db_table']}` (hostname, date, src_ip_addr, app_name) VALUES ('{$this->hostname}', '{$this->date}', '{$this->src_ip_addr}', '{$this->app_name}');";

		if (($result = $this->mysqli->query($query)) == FALSE)
			$this->error('Query failed: %s (%d)', $this->mysqli->error, $this->mysqli->errno);

		$this->insert_id = $this->mysqli->insert_id;
	}

	private function db_read() {
		$query = "SELECT hostname, date, src_ip_addr, app_name FROM `{$this->cfg['db_table']}` WHERE id = {$this->insert_id}";

		if (($result = $this->mysqli->query($query)) == false)
			$this->error('Query failed: %s (%d)', $this->mysqli->error, $this->mysqli->errno);

		$line = $result->fetch_assoc();

		if (!array_key_exists('hostname', $line) || !array_key_exists('date', $line) || !array_key_exists('src_ip_addr', $line) || !array_key_exists('app_name', $line))
			$this->error('Select query returned an invalid result, key(s) missing.');

		if ($line['hostname'] != $this->hostname)
			$this->error('Hostname: expected "%s", got "%s".', $this->hostname, $line['hostname']);

		if ($line['date'] != $this->date)
			$this->error('Date: expected "%s", got "%s".', $this->hostname, $line['host']);

		if ($line['src_ip_addr'] != $this->src_ip_addr)
			$this->error('Source IP address: expected "%s", got "%s".', $this->src_ip_addr, $line['src_ip_addr']);

		if ($line['app_name'] != $this->app_name)
			$this->error('Application name: expected "%s", got "%s".', $this->app_name, $line['app_name']);

		$result->close();
	}

	private function cleanup() {
		// Ignore any errors during cleanup.

		$this->disable_shutdown_function = true;

		if ($this->mysqli) {
			if ($this->insert_id >= 0)
				$this->mysqli->query("DELETE FROM `{$this->cfg['db_table']}` WHERE id = {$this->insert_id}");

			$this->mysqli->close();
		}

		closelog();
	}

	public function error_handler() {
		static $errors = array
			( E_ERROR	=> 'Fatal error'
			, E_WARNING	=> 'Warning'
			, E_PARSE	=> 'Parse error'
			, E_NOTICE	=> 'Notice'
			);

		if ($this->disable_shutdown_function)
			return;

		if (($error = error_get_last()) != null) {
			$this->error('PHP %s (type %d) on line %d in file %s: %s'
				, array_key_exists($error['type'], $errors) ? $errors[$error['type']] : 'Error'
				, $error['type'], $error['line'], $error['file'], $error['message']);
		}
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
		static $responses = array
			( 200 => 'OK'
			, 500 => 'Internal Server Error'
			);

		$response = array_key_exists($code, $responses) ? $responses[$code] : 'Unknown';

		if (!headers_sent()) {
			header("HTTP/1.0 $code $response");
			header('Content-type: text/html; charset=utf-8');
			header('Conection: close');
		}

		printf	( '<html><head><title>%1$d %2$s</title></head><body><h1>%1$d %2$s</h1>%3$s</body></html>' . "\n"
			, $code
			, $response
			, $msg != null ? "<p>$msg</p>" : ''
			);
	}
}

error_reporting(E_ALL);
ini_set('display_errors',1);
date_default_timezone_set('Europe/Zurich');
require_once(dirname(__FILE__) . '/../../../etc/zabbix-helpers/healthcheck-mysql.conf');
error_reporting(0);
ini_set('display_errors',0);

$hc = new HealthCheckMysql($_CONFIG);
$hc->run();
?>
