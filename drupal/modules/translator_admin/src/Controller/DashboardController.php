<?php

namespace Drupal\translator_admin\Controller;

use Drupal\Core\Controller\ControllerBase;

class DashboardController extends ControllerBase {

  public function dashboard() {
    // URL Public Dashboard của Superset
    $superset_url = 'http://localhost:8088/superset/dashboard/drupal/?standalone=true';

    return [
      '#type' => 'inline_template',
      '#template' => '<iframe src="{{ url }}" frameborder="0" width="100%" height="1000px"></iframe>',
      '#context' => ['url' => $superset_url],
    ];
  }

}