CREATE TABLE IF NOT EXISTS users (
  user_id INT AUTO_INCREMENT PRIMARY KEY,
  first_name VARCHAR(100) NOT NULL,
  last_name VARCHAR(100) NOT NULL,
  email VARCHAR(255) NOT NULL UNIQUE,
  call_user_id VARCHAR(30) NULL UNIQUE,
  password_hash VARCHAR(255) NOT NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS contacts (
  contact_id INT AUTO_INCREMENT PRIMARY KEY,
  user_id INT NOT NULL,
  contact_user_id INT NOT NULL,
  nickname VARCHAR(255) NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_contacts_user_id FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE,
  CONSTRAINT fk_contacts_contact_user_id FOREIGN KEY (contact_user_id) REFERENCES users(user_id) ON DELETE CASCADE,
  UNIQUE KEY uniq_contact_pair (user_id, contact_user_id)
);

CREATE TABLE IF NOT EXISTS calls (
  call_id INT AUTO_INCREMENT PRIMARY KEY,
  caller_id INT NOT NULL,
  receiver_id INT NOT NULL,
  call_status ENUM('missed','completed','ongoing') NOT NULL DEFAULT 'ongoing',
  started_at DATETIME NULL,
  ended_at DATETIME NULL,
  CONSTRAINT fk_calls_caller_id FOREIGN KEY (caller_id) REFERENCES users(user_id) ON DELETE CASCADE,
  CONSTRAINT fk_calls_receiver_id FOREIGN KEY (receiver_id) REFERENCES users(user_id) ON DELETE CASCADE,
  INDEX idx_calls_caller (caller_id),
  INDEX idx_calls_receiver (receiver_id)
);

CREATE TABLE call_participants (
    call_id INT NOT NULL,
    user_id INT NOT NULL,
    joined_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY(call_id, user_id),
    FOREIGN KEY(call_id) REFERENCES calls(call_id),
    FOREIGN KEY(user_id) REFERENCES users(user_id)
);

CREATE TABLE IF NOT EXISTS user_fcm_tokens (
  user_id INT NOT NULL,
  fcm_token VARCHAR(512) NOT NULL,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (user_id),
  CONSTRAINT fk_user_fcm_tokens_user_id FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE
);

